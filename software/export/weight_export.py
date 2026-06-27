"""Phase 1 — Quantize trained weights to Q8.8 and export as hex for hardware.

Loads the trained snnTorch model and writes Q8.8 (16-bit signed, 8 fractional
bits) fixed-point representations of every nn.Linear weight matrix, plus a
neuron threshold config file. Round-trip cosine similarity is checked to confirm
the quantization is faithful.

Run from the repo root:
    python software/export/weight_export.py
"""

import os
import sys

import numpy as np
import torch

# Make the shared model module importable (it lives in software/train/).
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "train"))
from snn_model import SNNNet, THRESHOLD  # noqa: E402

# --- Q8.8 fixed-point format ---
FRAC_BITS = 8
SCALE = 2 ** FRAC_BITS          # 256
INT16_MIN = -32768              # raw int16 range
INT16_MAX = 32767

MODEL_PATH = "software/train/snn_iris_trained.pt"
LAYER1_HEX = "hardware/mem/layer1_weights.hex"
LAYER2_HEX = "hardware/mem/layer2_weights.hex"
NEURON_HEX = "hardware/mem/neuron_cfg.hex"


def float_to_q8_8(w_float):
    """Quantize a float array to Q8.8 raw int16 values (clamped)."""
    w_int = np.round(w_float * SCALE).astype(np.int64)
    w_int = np.clip(w_int, INT16_MIN, INT16_MAX)
    return w_int.astype(np.int32)


def q8_8_to_float(w_int):
    """Dequantize Q8.8 raw int values back to float."""
    return w_int.astype(np.float64) / SCALE


def to_hex4(val):
    """Format a signed int as 4-digit two's-complement hex (16-bit)."""
    return f"{val & 0xFFFF:04X}"


def cosine_similarity(a, b):
    a, b = a.ravel(), b.ravel()
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b)))


def export_layer(name, weight_float, hex_path):
    """Quantize one weight matrix, write hex, and report stats. Returns cos sim."""
    w_int = float_to_q8_8(weight_float)
    w_deq = q8_8_to_float(w_int)

    # Write row-major, one 4-hex-digit value per line.
    lines = [to_hex4(int(v)) for v in w_int.ravel()]
    with open(hex_path, "w") as f:
        f.write("\n".join(lines) + "\n")

    q_err = float(np.mean(np.abs(weight_float - w_deq)))
    cos = cosine_similarity(weight_float, w_deq)

    print(f"\n[{name}] shape={weight_float.shape}  ->  {hex_path}")
    print(f"  float weights : min={weight_float.min():+.4f}  "
          f"max={weight_float.max():+.4f}")
    print(f"  Q8.8 raw int  : min={int(w_int.min()):+d}  "
          f"max={int(w_int.max()):+d}")
    print(f"  values written: {len(lines)}")
    print(f"  quant error   : mean|Δ| = {q_err:.6f}")
    print(f"  cosine sim    : {cos:.6f}  ({'OK' if cos > 0.999 else 'LOW'})")
    return cos, q_err, len(lines)


def main():
    ckpt = torch.load(MODEL_PATH, weights_only=False)
    model = SNNNet(beta=ckpt["config"]["beta"],
                   threshold=ckpt["config"]["threshold"])
    model.load_state_dict(ckpt["state_dict"])
    model.eval()

    print(f"Loaded model from {MODEL_PATH} "
          f"(test_acc={ckpt.get('test_acc', float('nan')):.3f})")
    print(f"Q8.8 format: SCALE={SCALE}, raw int16 range "
          f"[{INT16_MIN}, {INT16_MAX}]")

    w1 = model.fc1.weight.detach().numpy().astype(np.float64)  # [4, 8]
    w2 = model.fc2.weight.detach().numpy().astype(np.float64)  # [2, 4]

    cos1, err1, n1 = export_layer("layer1 (fc1)", w1, LAYER1_HEX)
    cos2, err2, n2 = export_layer("layer2 (fc2)", w2, LAYER2_HEX)

    # --- Neuron config: thresholds in Q8.8 (4 layer1 + 2 layer2 neurons) ---
    thr_q = to_hex4(int(round(THRESHOLD * SCALE)))
    neuron_lines = [thr_q] * 4 + [thr_q] * 2  # 4 hidden + 2 output neurons
    with open(NEURON_HEX, "w") as f:
        f.write("# threshold per neuron (Q8.8): 4x layer1, 2x layer2\n")
        f.write("\n".join(neuron_lines) + "\n")
    print(f"\n[neuron_cfg] thresholds={THRESHOLD} (Q8.8=0x{thr_q})  "
          f"-> {NEURON_HEX}  ({len(neuron_lines)} neurons)")

    # --- Round-trip verification ---
    print("\n=== Round-trip verification ===")
    overall_ok = cos1 > 0.999 and cos2 > 0.999
    print(f"  layer1 cosine similarity: {cos1:.6f}")
    print(f"  layer2 cosine similarity: {cos2:.6f}")
    print(f"  result: {'PASS (> 0.999)' if overall_ok else 'FAIL'}")

    # --- Final summary ---
    print("\n=== Summary ===")
    for path in (LAYER1_HEX, LAYER2_HEX, NEURON_HEX):
        size = os.path.getsize(path)
        print(f"  {path:<34} {size:>5} bytes")
    print(f"  total weights exported : {n1 + n2}")
    print(f"  mean quant error       : {(err1 + err2) / 2:.6f}")


if __name__ == "__main__":
    main()
