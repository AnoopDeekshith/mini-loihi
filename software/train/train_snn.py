"""Phase 1 — Train an 8->4->2 snnTorch LIF network on spike-encoded Iris.

Pipeline:
  1. Load Iris (binary subset), 4 features duplicated -> 8 inputs, normalized.
  2. 80/20 stratified train/test split.
  3. Rate-encode each feature into a 20-timestep Bernoulli spike train.
  4. Train the LIF network (50 epochs, Adam, cross-entropy on spike counts).
  5. Evaluate, save the model, and export the architecture to JSON.

Run from the repo root:
    python software/train/train_snn.py
"""

import json
import os

import numpy as np
import torch
import torch.nn as nn

# snn_model.py lives next to this script.
from snn_model import (
    SNNNet, load_iris_8input, rate_encode,
    N_STEPS, BETA, THRESHOLD, N_INPUTS, N_HIDDEN, N_OUTPUTS,
)

SEED = 42
N_EPOCHS = 50
LR = 1e-3

MODEL_PATH = "software/train/snn_iris_trained.pt"
PARAMS_PATH = "hardware/mem/model_params.json"


def evaluate(model, X, y, n_repeats=5):
    """Accuracy over n_repeats stochastic spike-encodings (averaged votes)."""
    model.eval()
    X_t = torch.tensor(X)
    y_t = torch.tensor(y)
    counts = torch.zeros(X_t.shape[0], N_OUTPUTS)
    with torch.no_grad():
        for _ in range(n_repeats):
            spk_in = rate_encode(X_t, N_STEPS)
            spk_count, _ = model(spk_in)
            counts += spk_count
    preds = counts.argmax(dim=1)
    return (preds == y_t).float().mean().item()


def main():
    torch.manual_seed(SEED)
    np.random.seed(SEED)

    # --- Data ---
    X_train, X_test, y_train, y_test = load_iris_8input(seed=SEED)
    print(f"Dataset: {X_train.shape[0]} train / {X_test.shape[0]} test, "
          f"{N_INPUTS} inputs, {N_OUTPUTS} classes")
    print(f"Encoding: {N_STEPS}-step rate code (Bernoulli)\n")

    X_train_t = torch.tensor(X_train)
    y_train_t = torch.tensor(y_train)

    # --- Model / optimizer / loss ---
    model = SNNNet(beta=BETA, threshold=THRESHOLD)
    optimizer = torch.optim.Adam(model.parameters(), lr=LR)
    loss_fn = nn.CrossEntropyLoss()

    # --- Training loop ---
    gen = torch.Generator().manual_seed(SEED)
    STEPS_PER_EPOCH = 5  # several fresh spike-encodings per epoch for stability
    for epoch in range(N_EPOCHS):
        model.train()
        epoch_loss = 0.0
        for _ in range(STEPS_PER_EPOCH):
            # Fresh stochastic encoding each step (data augmentation via noise).
            spk_in = rate_encode(X_train_t, N_STEPS, generator=gen)
            spk_count, _ = model(spk_in)        # [batch, 2] spike counts == logits
            loss = loss_fn(spk_count, y_train_t)

            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            epoch_loss += loss.item()
        epoch_loss /= STEPS_PER_EPOCH

        if (epoch + 1) % 10 == 0 or epoch == 0:
            train_acc = evaluate(model, X_train, y_train)
            print(f"epoch {epoch + 1:>3}/{N_EPOCHS}  "
                  f"loss={epoch_loss:.4f}  train_acc={train_acc:.3f}")

    # --- Final evaluation ---
    train_acc = evaluate(model, X_train, y_train)
    test_acc = evaluate(model, X_test, y_test)
    print(f"\nFinal train accuracy: {train_acc:.3f}")
    print(f"Final test  accuracy: {test_acc:.3f}")

    # --- Save model (state_dict + config for portable reload) ---
    torch.save(
        {
            "state_dict": model.state_dict(),
            "config": {
                "n_in": N_INPUTS, "n_hidden": N_HIDDEN, "n_out": N_OUTPUTS,
                "beta": BETA, "threshold": THRESHOLD, "n_steps": N_STEPS,
            },
            "test_acc": test_acc,
        },
        MODEL_PATH,
    )
    print(f"\nSaved trained model to {MODEL_PATH}")

    # --- Report learned dynamics (beta/threshold are fixed, not learned here) ---
    print("\nLayer parameters (LIF dynamics):")
    print(f"  layer1: beta={float(model.lif1.beta):.3f}  "
          f"threshold={float(model.lif1.threshold):.3f}  "
          f"weight shape={tuple(model.fc1.weight.shape)}")
    print(f"  layer2: beta={float(model.lif2.beta):.3f}  "
          f"threshold={float(model.lif2.threshold):.3f}  "
          f"weight shape={tuple(model.fc2.weight.shape)}")

    # --- Export architecture params for hardware ---
    params = {
        "layer1": {"beta": BETA, "threshold": THRESHOLD,
                   "n_in": N_INPUTS, "n_out": N_HIDDEN},
        "layer2": {"beta": BETA, "threshold": THRESHOLD,
                   "n_in": N_HIDDEN, "n_out": N_OUTPUTS},
    }
    os.makedirs(os.path.dirname(PARAMS_PATH), exist_ok=True)
    with open(PARAMS_PATH, "w") as f:
        json.dump(params, f, indent=2)
    print(f"Exported model params to {PARAMS_PATH}")


if __name__ == "__main__":
    main()
