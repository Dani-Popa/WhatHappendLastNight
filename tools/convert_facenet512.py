#!/usr/bin/env python3
"""
Convert the Sandberg FaceNet (20180402-114759, VGGFace2, 512-d) weights
into a CoreML .mlmodel that the Xcode target can load.

Local checkpoint location (informational)
-----------------------------------------
The original TF1 checkpoint files live at:
  /Users/Shared/Garmin/prj/mrn/github/WhatHappendLastNight/20180402-114759
    20180402-114759.pb
    model-20180402-114759.ckpt-275.{meta,index,data-00000-of-00001}

This script does NOT read those files directly — it instead uses
`facenet-pytorch`, which downloads a PyTorch port of the same VGGFace2
weights from its own mirror on first run. Identical architecture
(Inception-ResNet-v1), identical training set, identical 512-d head.
The local .pb is kept around as the canonical source of truth in case we
ever need to re-port the weights or verify provenance, but isn't part of
the conversion pipeline.

Why this script avoids TensorFlow
---------------------------------
The TF1 checkpoint would require `tensorflow==1.15` to load. TF 1.15 has
no wheels for Python ≥ 3.8 and none at all for arm64 Macs, so installing
it fresh on a modern machine is more pain than it's worth. PyTorch +
coremltools both have native arm64 builds, so this path works out of the
box on Apple Silicon.

Pinned versions (current, arm64-friendly)
-----------------------------------------
  python      3.10 / 3.11
  torch       2.x (any recent)
  facenet-pytorch 2.5.3+
  coremltools 7.x or 8.x

Clean venv:
  python3.11 -m venv .venv-convert
  source .venv-convert/bin/activate
  pip install --upgrade pip
  pip install torch facenet-pytorch coremltools pillow

Run
---
  python convert_facenet512.py --out FaceNet512_VGGFace2.mlmodel

The first run downloads the pretrained weights (~111 MB) into the
facenet-pytorch cache directory.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--out",
        type=Path,
        default=Path(__file__).parent / "FaceNet512_VGGFace2.mlmodel",
        help="Output CoreML model path.",
    )
    parser.add_argument(
        "--pretrained",
        choices=("vggface2", "casia-webface"),
        default="vggface2",
        help="Which Sandberg variant to convert. 20180402-114759 is vggface2.",
    )
    args = parser.parse_args()

    try:
        import torch
        from facenet_pytorch import InceptionResnetV1
        import coremltools as ct
    except ImportError as exc:
        print(
            f"Missing dependency: {exc.name}.\n"
            "  pip install torch facenet-pytorch coremltools pillow",
            file=sys.stderr,
        )
        return 1

    print(f"Loading InceptionResnetV1 (pretrained='{args.pretrained}')…")
    model = InceptionResnetV1(pretrained=args.pretrained).eval()

    # Trace with a representative tensor. PyTorch's NCHW layout matches what
    # CoreML's ImageType produces — channels first, RGB, 160×160.
    example = torch.rand(1, 3, 160, 160)
    print("Tracing model…")
    with torch.no_grad():
        traced = torch.jit.trace(model, example)

    print("Converting to CoreML — this can take a minute or two…")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.ImageType(
                name="input",
                shape=(1, 3, 160, 160),
                # FaceNet preprocessing: (pixel - 127.5) / 128.
                # CoreML applies (pixel * scale) + bias per channel.
                scale=1.0 / 128.0,
                bias=[-127.5 / 128.0] * 3,
                color_layout=ct.colorlayout.RGB,
            ),
        ],
        outputs=[ct.TensorType(name="embeddings")],
        minimum_deployment_target=ct.target.iOS15,
        convert_to="mlprogram",
    )

    mlmodel.short_description = (
        "FaceNet (Inception-ResNet-v1) trained on VGGFace2. "
        "512-d L2-normalized embedding, 160×160 RGB input. Weights from "
        "facenet-pytorch (Sandberg 20180402-114759 port)."
    )
    mlmodel.author = "David Sandberg (original); Tim Esler (PyTorch port); converted via convert_facenet512.py"
    mlmodel.license = "MIT"
    mlmodel.version = "20180402-114759"

    out = args.out
    out.parent.mkdir(parents=True, exist_ok=True)
    # `convert_to='mlprogram'` produces an .mlpackage. If the user asked for
    # a legacy .mlmodel filename we still write the .mlpackage alongside —
    # both work in Xcode.
    if out.suffix == ".mlmodel":
        out = out.with_suffix(".mlpackage")
    mlmodel.save(str(out))
    print(f"Wrote {out}")
    print(
        "Next: drag the .mlpackage into Xcode, add it to the "
        "WhatHappendLastNight target. FaceMatcher.swift already lists "
        "'20180402-114759' and 'FaceNet512_VGGFace2' in facenet512ModelNames, "
        "so the new picker entry will activate as soon as the bundle ships it."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
