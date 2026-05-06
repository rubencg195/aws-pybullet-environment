#!/usr/bin/env python3
"""
Headless PyBullet smoke: built-in plane + R2D2 from pybullet_data, TinyRenderer camera GIF, upload to S3.
Run on the GPU host (e.g. via SSM). Requires instance role with s3:PutObject on the artifacts bucket.
URDFs use the `pybullet_data` module shipped with the `pybullet` wheel (not a separate PyPI project).
Environment:
  PYBULLET_S3_BUCKET (required)
  PYBULLET_S3_PREFIX (optional, default sim-runs)
  EC2_INSTANCE_ID   (optional, for key prefix)
  AWS_REGION        (optional; boto3 uses instance metadata when on EC2)
"""
from __future__ import annotations

import io
import os
import subprocess
import sys
from datetime import datetime, timezone


def _ensure_deps() -> None:
    # URDF assets ship with the pybullet wheel (`pybullet_data` module); not a separate PyPI project.
    try:
        import pybullet as _p  # noqa: F401
        import pybullet_data  # noqa: F401
    except ImportError:
        subprocess.check_call(
            [sys.executable, "-m", "pip", "install", "-q", "pybullet"],
            stdout=subprocess.DEVNULL,
        )
    try:
        import boto3  # noqa: F401
    except ImportError:
        subprocess.check_call(
            [sys.executable, "-m", "pip", "install", "-q", "boto3"],
            stdout=subprocess.DEVNULL,
        )


def _joint_name(robot, j: int, p) -> str:
    inf = p.getJointInfo(robot, j)
    raw = inf[1]
    return raw.decode("utf-8", errors="ignore") if isinstance(raw, bytes) else str(raw)


def _revolute_like_types(p):
    """PyBullet 3.2+ exposes JOINT_CONTINUOUS; older wheels are often JOINT_REVOLUTE only."""
    types = [p.JOINT_REVOLUTE]
    c = getattr(p, "JOINT_CONTINUOUS", None)
    if c is not None:
        types.append(c)
    return tuple(types)


def _classify_joints(robot, p):
    """Drive joints: legs/wheels/motors. Body: head/neck/arms only (Bullet R2-D2 often names legs without 'wheel')."""
    drive_js: list[int] = []
    body_js: list[int] = []
    rev_like = _revolute_like_types(p)
    head_kw = ("head", "neck", "eye", "antenna", "periscope", "sensor")
    arm_kw = ("gripper", "finger", "hand", "arm", "wrist", "elbow", "shoulder", "tool")
    drive_kw = (
        "wheel",
        "caster",
        "castor",
        "hub",
        "motor",
        "leg",
        "foot",
        "ankle",
        "roller",
        "drive",
        "base",
        "bogie",
    )
    for j in range(p.getNumJoints(robot)):
        inf = p.getJointInfo(robot, j)
        jtype = inf[2]
        if jtype not in rev_like:
            continue
        n = _joint_name(robot, j, p).lower()
        if any(k in n for k in head_kw) or any(k in n for k in arm_kw):
            body_js.append(j)
        elif any(k in n for k in drive_kw):
            drive_js.append(j)
        else:
            # Unlabeled R2-D2 joints are usually leg/foot mechanics — drive those, not the dome.
            drive_js.append(j)
    return drive_js, body_js


def main() -> int:
    _ensure_deps()

    import boto3
    import numpy as np
    import pybullet as p
    import pybullet_data
    from PIL import Image

    bucket = os.environ.get("PYBULLET_S3_BUCKET")
    if not bucket:
        print("ERROR: set PYBULLET_S3_BUCKET", file=sys.stderr)
        return 1

    prefix = os.environ.get("PYBULLET_S3_PREFIX", "sim-runs").strip("/")
    instance = os.environ.get("EC2_INSTANCE_ID", "unknown-instance")

    # --- Simulation tuning (longer real-time, grounded contact, visible motion) ---
    sim_hz = 240.0
    settle_steps = 500
    motion_steps = 2600
    capture_every = 7
    gif_frame_ms = 85

    p.connect(p.DIRECT)
    p.setAdditionalSearchPath(pybullet_data.getDataPath())
    p.setGravity(0, 0, -9.81)
    p.setTimeStep(1.0 / sim_hz)
    p.setPhysicsEngineParameter(numSolverIterations=24, numSubSteps=1)

    plane = p.loadURDF("plane.urdf", useFixedBase=True)
    p.changeDynamics(plane, -1, lateralFriction=1.4, spinningFriction=0.04, restitution=0.0)

    # Start low so the chassis/wheels meet the plane; avoid a high spawn that reads as "floating".
    robot = p.loadURDF(
        "r2d2.urdf",
        basePosition=[0.0, 0.0, 0.06],
        baseOrientation=p.getQuaternionFromEuler([0.0, 0.0, 0.0]),
        useFixedBase=False,
    )
    p.changeDynamics(robot, -1, linearDamping=0.08, angularDamping=0.12)

    num_joints = p.getNumJoints(robot)
    for j in range(-1, num_joints):
        p.changeDynamics(robot, j, lateralFriction=1.0)

    wheel_js, body_js = _classify_joints(robot, p)
    if not wheel_js:
        # Fallback: actuate lowest-index revolute joints (often legs before head in URDF order).
        rev_like = _revolute_like_types(p)
        cand = [j for j in range(num_joints) if p.getJointInfo(robot, j)[2] in rev_like]
        wheel_js = [j for j in cand if j not in body_js][:6] or cand[:4]

    # Let gravity and contacts resolve before recording (fixes "hovering" look from too-few steps).
    for _ in range(settle_steps):
        p.stepSimulation()

    width, height = 360, 270
    frames: list[Image.Image] = []

    for t in range(motion_steps):
        # Piecewise "mission": forward cruise, spin, reverse — makes motion obvious on the plane.
        seg = t / motion_steps
        if seg < 0.35:
            drive = 5.5
            steer_bias = 0.6 * np.sin(t / 55.0)
        elif seg < 0.55:
            drive = 0.8
            steer_bias = 4.2 * np.sin(t / 14.0)
        elif seg < 0.8:
            drive = -4.0
            steer_bias = -0.5 * np.sin(t / 40.0)
        else:
            drive = 3.0 * np.sin(t / 25.0)
            steer_bias = 2.5 * np.sin(t / 18.0)

        half = max(1, (len(wheel_js) + 1) // 2)
        for i, j in enumerate(wheel_js):
            # Split wheel set so steer_bias creates a turn (differential-style).
            side = -1.0 if i < half else 1.0
            target = drive + steer_bias * side + 1.2 * np.sin(t / 11.0 + i)
            p.setJointMotorControl2(
                robot,
                j,
                p.VELOCITY_CONTROL,
                targetVelocity=float(target),
                force=120.0,
            )
        for j in body_js:
            # Keep head motion subtle so leg/base motion reads as the main action.
            p.setJointMotorControl2(
                robot,
                j,
                p.VELOCITY_CONTROL,
                targetVelocity=float(0.9 * np.sin(t / 14.0 + j * 0.5)),
                force=6.0,
            )

        # Whole-body nudge: R2-D2 URDF often hides wheel motion; forces/torques make translation/yaw obvious.
        world = getattr(p, "WORLD_FRAME", 2)
        fx = 260.0 * np.sin(t / 48.0) + 160.0 * np.sin(t / 110.0)
        fy = 190.0 * np.cos(t / 42.0)
        tz = 110.0 * np.sin(t / 36.0)
        p.applyExternalForce(
            robot,
            -1,
            forceObj=[float(fx), float(fy), 0.0],
            posObj=[0, 0, 0],
            flags=world,
        )
        p.applyExternalTorque(robot, -1, torqueObj=[0, 0, float(tz)], flags=world)

        p.stepSimulation()

        if t % capture_every != 0:
            continue

        pos, _orn = p.getBasePositionAndOrientation(robot)
        tx, ty = float(pos[0]), float(pos[1])
        yaw = 42.0 + (t * 0.18)
        view = p.computeViewMatrixFromYawPitchRoll(
            cameraTargetPosition=[tx, ty, 0.22],
            distance=2.55,
            yaw=yaw,
            pitch=-24.0,
            roll=0,
            upAxisIndex=2,
        )
        proj = p.computeProjectionMatrixFOV(
            fov=52,
            aspect=width / height,
            nearVal=0.04,
            farVal=18.0,
        )
        _, _, rgba, _, _ = p.getCameraImage(
            width,
            height,
            viewMatrix=view,
            projectionMatrix=proj,
            renderer=p.ER_TINY_RENDERER,
        )
        arr = np.asarray(rgba, dtype=np.uint8).reshape((height, width, 4))
        rgb = arr[:, :, :3]
        frames.append(Image.fromarray(rgb))

    p.disconnect()

    if not frames:
        print("ERROR: no frames captured", file=sys.stderr)
        return 1

    buf = io.BytesIO()
    frames[0].save(
        buf,
        format="GIF",
        save_all=True,
        append_images=frames[1:],
        duration=gif_frame_ms,
        loop=0,
    )
    buf.seek(0)

    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    key = f"{prefix}/{instance}/{ts}/r2d2_plane_sim.gif"

    boto3.client("s3").upload_fileobj(
        buf,
        bucket,
        key,
        ExtraArgs={"ContentType": "image/gif"},
    )
    print(f"OK: s3://{bucket}/{key}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
