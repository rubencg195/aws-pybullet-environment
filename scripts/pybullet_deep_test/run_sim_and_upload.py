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


def _classify_joints(robot, p):
    """Split actuated joints into wheel-like vs body/head (for R2-D2 URDF naming variants)."""
    wheel_js: list[int] = []
    body_js: list[int] = []
    for j in range(p.getNumJoints(robot)):
        inf = p.getJointInfo(robot, j)
        jtype = inf[2]
        if jtype not in (p.JOINT_REVOLUTE, p.JOINT_CONTINUOUS):
            continue
        n = _joint_name(robot, j, p).lower()
        if any(k in n for k in ("wheel", "caster", "castor", "hub", "motor")):
            wheel_js.append(j)
        else:
            body_js.append(j)
    return wheel_js, body_js


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
        # Older/alternate URDFs: drive first few revolute joints so something still moves.
        wheel_js = [j for j in range(min(4, num_joints)) if p.getJointInfo(robot, j)[2] in (p.JOINT_REVOLUTE, p.JOINT_CONTINUOUS)]

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
                force=85.0,
            )
        for j in body_js:
            p.setJointMotorControl2(
                robot,
                j,
                p.VELOCITY_CONTROL,
                targetVelocity=float(2.8 * np.sin(t / 9.0 + j * 0.7)),
                force=12.0,
            )

        p.stepSimulation()

        if t % capture_every != 0:
            continue

        yaw = 42.0 + (t * 0.22)
        view = p.computeViewMatrixFromYawPitchRoll(
            cameraTargetPosition=[0.0, 0.0, 0.22],
            distance=2.45,
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
