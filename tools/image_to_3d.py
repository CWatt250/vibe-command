#!/usr/bin/env python3
"""Image-to-3D spike: a unit portrait -> GLB mesh via ComfyUI's native Hunyuan3D-2 nodes.

    ~/AI_Agent/venv/bin/python tools/image_to_3d.py VC-U04 [--steps 30] [--octree 256]

Assumes ComfyUI is up on 127.0.0.1:8188 with models/checkpoints/hunyuan3d-dit-v2.safetensors.
Feeds assets/portraits/<id>.png (already keyed to alpha, which is what the model wants), waits,
and copies the GLB to ~/Dev/assets/generated3d/<id>.glb for tools/render_sprites.py to kitbash.
"""
import argparse
import glob
import json
import os
import shutil
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMFY = os.path.expanduser("~/Dev/ComfyUI")
URL = "http://127.0.0.1:8188"
OUT_DIR = os.path.expanduser("~/Dev/assets/generated3d")


def pad_portrait(src: str, dst: str, margin: float) -> None:
    """Centre the portrait on a square transparent canvas with `margin` free on every
    side. Portraits come out of ai_sprite_prep cropped flush to their bbox; feeding an
    edge-to-edge subject makes the reconstruction clip against the voxel bounds — legs
    and extremities come back sheared off against a flat plane."""
    from PIL import Image
    im = Image.open(src).convert("RGBA")
    # Binarise alpha first. ai_sprite_prep's key leaves a soft halo wherever the
    # generated backdrop wasn't magenta enough — worst on dark subjects (the SG
    # roster, TS-U05), where over half the canvas comes back semi-transparent.
    # Hunyuan3D treats any non-zero alpha as subject and reconstructs that halo as
    # a flat slab standing behind the unit, which then renders as a grey box.
    import numpy as np
    arr = np.array(im)
    arr[..., 3] = np.where(arr[..., 3] >= 150, 255, 0).astype(arr.dtype)
    im = Image.fromarray(arr, "RGBA")
    box = im.getbbox() or (0, 0, im.width, im.height)
    im = im.crop(box)
    side = int(max(im.width, im.height) * (1.0 + 2.0 * margin))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(im, ((side - im.width) // 2, (side - im.height) // 2))
    canvas.save(dst)


def workflow(image_name: str, seed: int, steps: int, octree: int, prefix: str) -> dict:
    return {
        "1": {"class_type": "ImageOnlyCheckpointLoader", "inputs": {"ckpt_name": "hunyuan3d-dit-v2.safetensors"}},
        "2": {"class_type": "LoadImage", "inputs": {"image": image_name}},
        "3": {"class_type": "CLIPVisionEncode", "inputs": {"clip_vision": ["1", 1], "image": ["2", 0], "crop": "center"}},
        "4": {"class_type": "Hunyuan3Dv2Conditioning", "inputs": {"clip_vision_output": ["3", 0]}},
        "5": {"class_type": "EmptyLatentHunyuan3Dv2", "inputs": {"resolution": 3072, "batch_size": 1}},
        "6": {"class_type": "KSampler", "inputs": {
            "model": ["1", 0], "seed": seed, "steps": steps, "cfg": 5.0,
            "sampler_name": "euler", "scheduler": "simple", "denoise": 1.0,
            "positive": ["4", 0], "negative": ["4", 1], "latent_image": ["5", 0]}},
        "7": {"class_type": "VAEDecodeHunyuan3D", "inputs": {
            "samples": ["6", 0], "vae": ["1", 2], "num_chunks": 8000, "octree_resolution": octree}},
        "8": {"class_type": "VoxelToMesh", "inputs": {"voxel": ["7", 0], "algorithm": "surface net", "threshold": 0.6}},
        "9": {"class_type": "SaveGLB", "inputs": {"mesh": ["8", 0], "filename_prefix": prefix}},
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("unit_id")
    ap.add_argument("--steps", type=int, default=30)
    ap.add_argument("--octree", type=int, default=256)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--margin", type=float, default=0.18)
    ap.add_argument("--image", default=None,
                     help="use this image instead of assets/portraits/<unit_id>.png")
    ap.add_argument("--out-id", default=None,
                     help="output basename instead of <unit_id> (for --image inputs keyed "
                          "by a different id, e.g. a structure sprite)")
    a = ap.parse_args()

    out_id = a.out_id or a.unit_id
    src = os.path.join(ROOT, a.image) if a.image else os.path.join(ROOT, "assets", "portraits", f"{a.unit_id}.png")
    if not os.path.exists(src):
        sys.exit(f"no portrait at {src}")
    image_name = f"i23d_{out_id}.png"
    pad_portrait(src, os.path.join(COMFY, "input", image_name), a.margin)
    prefix = f"mesh/{out_id}"
    wf = workflow(image_name, a.seed, a.steps, a.octree, prefix)

    req = urllib.request.Request(f"{URL}/prompt", data=json.dumps({"prompt": wf}).encode(),
                                 headers={"Content-Type": "application/json"})
    try:
        pid = json.loads(urllib.request.urlopen(req, timeout=60).read())["prompt_id"]
    except urllib.error.HTTPError as e:
        sys.exit("workflow rejected: " + e.read().decode()[:1500])
    t0 = time.time()
    print("queued", pid, flush=True)
    while time.time() - t0 < 1800:
        time.sleep(4)
        try:
            h = json.loads(urllib.request.urlopen(f"{URL}/history/{pid}", timeout=30).read())
        except Exception:
            continue
        if pid not in h:
            continue
        st = h[pid].get("status", {})
        if st.get("status_str") == "error":
            for m in st.get("messages", []):
                if m[0] == "execution_error":
                    sys.exit("ERROR: " + str(m[1].get("exception_message"))[:800])
            sys.exit("ERROR (no detail)")
        if st.get("completed"):
            break
    else:
        sys.exit("timed out")
    cands = sorted(glob.glob(os.path.join(COMFY, "output", "mesh", f"{out_id}*.glb")), key=os.path.getmtime)
    if not cands:
        sys.exit("completed but no GLB found under output/mesh/")
    os.makedirs(OUT_DIR, exist_ok=True)
    dst = os.path.join(OUT_DIR, f"{out_id}.glb")
    shutil.copy2(cands[-1], dst)
    print(f"{dst}  ({os.path.getsize(dst) / 1e6:.1f} MB, {time.time() - t0:.0f}s)")


if __name__ == "__main__":
    main()
