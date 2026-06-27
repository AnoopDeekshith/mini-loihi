"""Phase 1 — Verify Q8.8 quantization preserves SNN behavior.

Loads the original float model and a quantized model (built from the exported
hex weight files, dequantized back to float), then runs the same spike-encoded
test samples through both and compares predictions class-for-class. The accuracy
loss from quantization should be < 5%.

Run from the repo root:
    python software/export/verify_quantization.py
"""

import os
import sys

import numpy as np
import torch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "train"))
from snn_model import (  # noqa: E402
    SNNNet, load_iris_8input, rate_encode, N_STEPS,
)

FRAC_BITS = 8
SCALE = 2 ** FRAC_BITS

MODEL_PATH = "software/train/snn_iris_trained.pt"
LAYER1_HEX = "hardware/mem/layer1_weights.hex"
LAYER2_HEX = "hardware/mem/layer2_weights.hex"

N_SAMPLES = 20
SEED = 7


def read_hex_weights(path, shape):
    """Read a hex weight file (4-digit two's-complement int16) -> float array."""
    vals = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            raw = int(line, 16)
            if raw >= 0x8000:           # sign-extend 16-bit two's complement
                raw -= 0x10000
            vals.append(raw)
    arr = np.array(vals, dtype=np.float64).reshape(shape) / SCALE
    return arr.astype(np.float32)


def build_quantized_model(ref_model):
    """Clone the architecture but load dequantized hex weights."""
    qmodel = SNNNet(beta=float(ref_model.lif1.beta),
                    threshold=float(ref_model.lif1.threshold))
    w1 = read_hex_weights(LAYER1_HEX, ref_model.fc1.weight.shape)
    w2 = read_hex_weights(LAYER2_HEX, ref_model.fc2.weight.shape)
    with torch.no_grad():
        qmodel.fc1.weight.copy_(torch.tensor(w1))
        qmodel.fc2.weight.copy_(torch.tensor(w2))
    qmodel.eval()
    return qmodel


def main():
    # --- Load float model ---
    ckpt = torch.load(MODEL_PATH, weights_only=False)
    fmodel = SNNNet(beta=ckpt["config"]["beta"],
                    threshold=ckpt["config"]["threshold"])
    fmodel.load_state_dict(ckpt["state_dict"])
    fmodel.eval()

    # --- Build quantized model from the exported hex files ---
    qmodel = build_quantized_model(fmodel)

    # --- Test data (use up to N_SAMPLES test points) ---
    _, X_test, _, y_test = load_iris_8input(seed=42)
    n = min(N_SAMPLES, X_test.shape[0])
    X = torch.tensor(X_test[:n])
    y = y_test[:n]

    # Identical spike encoding for both models -> isolates the weight effect.
    gen = torch.Generator().manual_seed(SEED)
    spk_in = rate_encode(X, N_STEPS, generator=gen)

    with torch.no_grad():
        f_count, _ = fmodel(spk_in)
        q_count, _ = qmodel(spk_in)
    f_pred = f_count.argmax(dim=1).numpy()
    q_pred = q_count.argmax(dim=1).numpy()

    # --- Side-by-side predictions ---
    print(f"Running {n} test samples through Float vs Quantized models\n")
    print(f"{'#':>3} | {'true':>4} | {'Float':>5} | {'Quant':>5} | {'match':>5}")
    print("-" * 36)
    agree = 0
    for i in range(n):
        same = f_pred[i] == q_pred[i]
        agree += int(same)
        print(f"{i:>3} | {int(y[i]):>4} | {int(f_pred[i]):>5} | "
              f"{int(q_pred[i]):>5} | {'yes' if same else 'NO':>5}")

    f_acc = float(np.mean(f_pred == y))
    q_acc = float(np.mean(q_pred == y))
    acc_loss = f_acc - q_acc

    print("\n=== Results ===")
    print(f"  Float     accuracy : {f_acc:.3f}")
    print(f"  Quantized accuracy : {q_acc:.3f}")
    print(f"  Float vs Quant agreement : {agree}/{n} ({100 * agree / n:.1f}%)")
    print(f"  Quantization accuracy loss : {100 * acc_loss:+.2f}% "
          f"({'PASS (< 5%)' if abs(acc_loss) < 0.05 else 'FAIL'})")


if __name__ == "__main__":
    main()
