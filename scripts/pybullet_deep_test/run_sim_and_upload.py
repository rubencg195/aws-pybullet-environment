#!/usr/bin/env python3
"""
Headless PyBullet smoke: built-in plane + R2D2 from pybullet_data, TinyRenderer camera GIF, upload to S3.
Run on the GPU host (e.g. via SSM). Requires instance role with s3:PutObject on the artifacts bucket.
URDFs use the `pybullet_data` module shipped with the `pybullet` wheel (not a separate pip package).
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

    p.connect(p.DIRECT)
    p.setAdditionalSearchPath(pybullet_data.getDataPath())
    p.setGravity(0, 0, -9.81)
    p.loadURDF("plane.urdf")
    robot = p.loadURDF("r2d2.urdf", basePosition=[0, 0, 0.2], useFixedBase=False)

    num_joints = p.getNumJoints(robot)
    width, height = 320, 240
    frames: list[Image.Image] = []

    steps = 180
    for t in range(steps):
        for j in range(min(6, num_joints)):
            p.setJointMotorControl2(
                robot,
                j,
                p.VELOCITY_CONTROL,
                targetVelocity=1.8 * np.sin(t / 12.0 + j),
                force=8.0,
            )
        p.stepSimulation()

        if t % 4 != 0:
            continue

        yaw = 30.0 + (t * 0.35)
        view = p.computeViewMatrixFromYawPitchRoll(
            cameraTargetPosition=[0, 0, 0.35],
            distance=2.2,
            yaw=yaw,
            pitch=-18.0,
            roll=0,
        )
        proj = p.computeProjectionMatrixFOV(
            fov=55,
            aspect=width / height,
            nearVal=0.05,
            farVal=12.0,
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
        duration=80,
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
