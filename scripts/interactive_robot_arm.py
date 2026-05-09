#!/usr/bin/env python3
"""
Interactive Kuka robot arm with per-joint sliders (degrees) and live FPS counter.

Run on the DCV desktop (needs a display):
    source /opt/pybullet-venv/bin/activate
    python3 interactive_robot_arm.py

Optional flags:
    --record FILE       Capture the GUI viewport to an animated GIF.
    --fps 15            GIF frame rate (default 15).
    --width 800         Capture width  (default 800).
    --height 600        Capture height (default 600).
    --s3-bucket BUCKET  Upload the GIF to this S3 bucket after recording.
    --s3-prefix PREFIX  S3 key prefix (default: sim-runs).

Controls:
    - One slider per revolute joint (in degrees).
    - Drag a slider to move the corresponding joint in real time.
    - FPS is printed in the terminal every second.
    - Press Ctrl-C or close the GUI window to stop (and save, if recording).
"""
from __future__ import annotations

import argparse
import math
import os
import sys
import time

try:
    import pybullet as p
    import pybullet_data
except ImportError:
    sys.exit("pybullet is not installed. Run: pip install pybullet")


def _parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Interactive Kuka arm with optional GIF recording.")
    ap.add_argument("--record", metavar="FILE", help="Save session to an animated GIF (e.g. session.gif).")
    ap.add_argument("--fps", type=int, default=15, help="GIF frame rate (default 15).")
    ap.add_argument("--width", type=int, default=800, help="Capture width (default 800).")
    ap.add_argument("--height", type=int, default=600, help="Capture height (default 600).")
    ap.add_argument("--s3-bucket", metavar="BUCKET", help="Upload GIF to this S3 bucket.")
    ap.add_argument("--s3-prefix", metavar="PREFIX", default="sim-runs", help="S3 key prefix (default sim-runs).")
    return ap.parse_args()


def main() -> int:
    args = _parse_args()

    recording = args.record is not None
    if recording:
        try:
            import numpy as np  # noqa: F401
            from PIL import Image  # noqa: F401
        except ImportError:
            sys.exit("Recording needs numpy + Pillow. Run: pip install numpy Pillow")

    cid = p.connect(p.GUI)
    if cid < 0:
        sys.exit("Could not open the PyBullet GUI (is a display available?)")

    p.setAdditionalSearchPath(pybullet_data.getDataPath())
    p.setGravity(0, 0, -9.81)
    p.setRealTimeSimulation(1)

    p.configureDebugVisualizer(p.COV_ENABLE_GUI, 1)
    p.configureDebugVisualizer(p.COV_ENABLE_SHADOWS, 1)
    p.resetDebugVisualizerCamera(cameraDistance=2.16, cameraYaw=45, cameraPitch=-30, cameraTargetPosition=[0, 0, 0.4])

    p.loadURDF("plane.urdf", useFixedBase=True)

    robot = p.loadURDF(
        "kuka_iiwa/model.urdf",
        basePosition=[0, 0, 0],
        useFixedBase=True,
    )

    num_joints = p.getNumJoints(robot)

    sliders: list[tuple[int, int, float, float]] = []
    for j in range(num_joints):
        info = p.getJointInfo(robot, j)
        jtype = info[2]
        if jtype not in (p.JOINT_REVOLUTE, getattr(p, "JOINT_CONTINUOUS", p.JOINT_REVOLUTE)):
            continue
        name = info[1].decode("utf-8", errors="replace")
        lo_rad, hi_rad = float(info[8]), float(info[9])
        if lo_rad >= hi_rad:
            lo_rad, hi_rad = -math.pi, math.pi
        lo_deg = math.degrees(lo_rad)
        hi_deg = math.degrees(hi_rad)
        sid = p.addUserDebugParameter(f"J{j} {name} (deg)", lo_deg, hi_deg, 0.0)
        sliders.append((j, sid, lo_rad, hi_rad))

    if not sliders:
        print("No revolute joints found in the URDF.", flush=True)
        return 1

    print(f"Loaded {len(sliders)} joint sliders. Drag them in the GUI.", flush=True)
    if recording:
        print(f"Recording to {os.path.abspath(args.record)} at {args.fps} fps ({args.width}x{args.height}).", flush=True)
        if args.s3_bucket:
            print(f"Will upload to s3://{args.s3_bucket}/{args.s3_prefix}/... on exit.", flush=True)
    print("Ctrl-C or close the window to stop (and save/upload if recording).\n", flush=True)

    frames: list = []
    capture_interval = 1.0 / args.fps if recording else 0.0
    last_capture = 0.0

    frame_count = 0
    fps_time = time.monotonic()

    try:
        while True:
            try:
                connected = p.isConnected()
            except Exception:
                connected = False
            if not connected:
                print("\nGUI window closed.")
                break

            for j_idx, sid, lo_rad, hi_rad in sliders:
                deg = p.readUserDebugParameter(sid)
                rad = math.radians(deg)
                rad = max(lo_rad, min(hi_rad, rad))
                p.setJointMotorControl2(
                    robot, j_idx, p.POSITION_CONTROL,
                    targetPosition=rad, force=500.0, maxVelocity=2.0,
                )

            if recording:
                now_t = time.monotonic()
                if now_t - last_capture >= capture_interval:
                    import numpy as np
                    from PIL import Image

                    cam = p.getDebugVisualizerCamera()
                    view = p.computeViewMatrixFromYawPitchRoll(
                        cameraTargetPosition=cam[11],
                        distance=cam[10],
                        yaw=cam[8],
                        pitch=cam[9],
                        roll=0,
                        upAxisIndex=2,
                    )
                    proj = p.computeProjectionMatrixFOV(
                        fov=60, aspect=args.width / args.height,
                        nearVal=0.1, farVal=100.0,
                    )
                    _, _, rgba, _, _ = p.getCameraImage(
                        args.width, args.height,
                        viewMatrix=view, projectionMatrix=proj,
                        renderer=p.ER_TINY_RENDERER,
                    )
                    arr = np.asarray(rgba, dtype=np.uint8).reshape((args.height, args.width, 4))
                    frames.append(Image.fromarray(arr[:, :, :3]))
                    last_capture = now_t

            frame_count += 1
            now = time.monotonic()
            elapsed = now - fps_time
            if elapsed >= 1.0:
                fps = frame_count / elapsed
                rec_info = f"  frames: {len(frames)}" if recording else ""
                print(f"\rFPS: {fps:6.1f}{rec_info}", end="", flush=True)
                frame_count = 0
                fps_time = now

            time.sleep(1.0 / 240.0)

    except KeyboardInterrupt:
        print("\nCtrl-C received.")
    except Exception as exc:
        print(f"\nLoop ended: {exc}")

    try:
        if p.isConnected():
            p.disconnect()
    except Exception:
        pass

    # ── Save GIF ──
    _save_and_upload(args, frames)

    return 0


def _save_and_upload(args: argparse.Namespace, frames: list) -> None:
    """Save the recorded frames to disk and optionally upload to S3."""
    import os

    recording = args.record is not None
    if not recording:
        return

    if not frames:
        print("\nNo frames captured (session was too short).")
        return

    from PIL import Image  # noqa: F811

    out_path = os.path.abspath(args.record)
    duration_ms = int(1000 / args.fps)

    print(f"\nEncoding {len(frames)} frames ({args.width}x{args.height} @ {args.fps} fps) ...")
    frames[0].save(
        out_path,
        format="GIF",
        save_all=True,
        append_images=frames[1:],
        duration=duration_ms,
        loop=0,
    )
    size_mb = os.path.getsize(out_path) / (1024 * 1024)
    print(f"Saved locally: {out_path}  ({size_mb:.1f} MB)")

    if not args.s3_bucket:
        return

    try:
        import boto3
    except ImportError:
        print("WARNING: boto3 not installed, skipping S3 upload.")
        return

    from datetime import datetime, timezone

    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    basename = os.path.basename(out_path)
    key = f"{args.s3_prefix}/{ts}/{basename}"
    s3_uri = f"s3://{args.s3_bucket}/{key}"

    print(f"Uploading to {s3_uri} ...")
    boto3.client("s3").upload_file(
        out_path,
        args.s3_bucket,
        key,
        ExtraArgs={"ContentType": "image/gif"},
    )
    print(f"OK: {s3_uri}")
    print(f"\nTo download later:\n  ./scripts/download-pybullet-sim-recording.sh '{s3_uri}'")


if __name__ == "__main__":
    raise SystemExit(main())
