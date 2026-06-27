"""Shared SNN model definition and data pipeline for the mini-loihi project.

Centralizing the architecture here lets train_snn.py, weight_export.py, and
verify_quantization.py all build/load the *exact* same network without
duplicating the definition or relying on pickling the __main__ module.

Architecture (Phase 1):
    fc1  = nn.Linear(8, 4, bias=False)
    lif1 = snn.Leaky(beta=0.9, threshold=1.0, reset_mechanism='zero')
    fc2  = nn.Linear(4, 2, bias=False)
    lif2 = snn.Leaky(beta=0.9, threshold=1.0, reset_mechanism='zero')

Inputs are rate-coded into N_STEPS-timestep Bernoulli spike trains; the network
is run over time and classification is done on per-class output spike counts.
"""

import numpy as np
import torch
import torch.nn as nn
import snntorch as snn

# --- Fixed hyperparameters shared across the pipeline ---
N_INPUTS = 8
N_HIDDEN = 4
N_OUTPUTS = 2
N_STEPS = 20
BETA = 0.9
THRESHOLD = 1.0


class SNNNet(nn.Module):
    """8 -> 4 -> 2 leaky integrate-and-fire network (bias-free, like hardware)."""

    def __init__(self, beta=BETA, threshold=THRESHOLD):
        super().__init__()
        self.fc1 = nn.Linear(N_INPUTS, N_HIDDEN, bias=False)
        self.lif1 = snn.Leaky(beta=beta, threshold=threshold,
                              reset_mechanism="zero")
        self.fc2 = nn.Linear(N_HIDDEN, N_OUTPUTS, bias=False)
        self.lif2 = snn.Leaky(beta=beta, threshold=threshold,
                              reset_mechanism="zero")

    def forward(self, spk_in):
        """Run the network over time.

        Args:
            spk_in: spike tensor of shape [N_STEPS, batch, N_INPUTS].

        Returns:
            spk2_count: summed output spikes per class, shape [batch, N_OUTPUTS].
            spk2_rec:   per-timestep output spikes, shape [N_STEPS, batch, 2].
        """
        mem1 = self.lif1.init_leaky()
        mem2 = self.lif2.init_leaky()

        spk2_rec = []
        n_steps = spk_in.shape[0]
        for t in range(n_steps):
            cur1 = self.fc1(spk_in[t])
            spk1, mem1 = self.lif1(cur1, mem1)
            cur2 = self.fc2(spk1)
            spk2, mem2 = self.lif2(cur2, mem2)
            spk2_rec.append(spk2)

        spk2_rec = torch.stack(spk2_rec)          # [N_STEPS, batch, 2]
        spk2_count = spk2_rec.sum(dim=0)          # [batch, 2]
        return spk2_count, spk2_rec


def load_iris_8input(seed=42):
    """Load Iris as a binary task with 8 inputs (4 features duplicated x2).

    The mini-loihi network has 2 output neurons, so we use a 2-class subset of
    Iris (setosa vs versicolor — reliably separable, giving a clean Phase-1
    accuracy target for the downstream quantization comparison). Each of the 4
    normalized features is repeated twice to produce 8 input neurons, matching
    the 8-input hardware datapath.

    Returns:
        X_train, X_test, y_train, y_test as float32 / int64 numpy arrays.
        Features are normalized to [0, 1].
    """
    from sklearn.datasets import load_iris
    from sklearn.model_selection import train_test_split

    data = load_iris()
    X, y = data.data, data.target

    # Binary subset: classes 0 (setosa) and 1 (versicolor).
    mask = y != 2
    X, y = X[mask], y[mask]
    y = (y == 1).astype(np.int64)  # 0 = setosa, 1 = versicolor

    # Normalize each feature to [0, 1].
    X = X.astype(np.float32)
    X_min, X_max = X.min(axis=0), X.max(axis=0)
    X = (X - X_min) / (X_max - X_min)

    # Duplicate each of the 4 features twice -> 8 input neurons.
    X8 = np.repeat(X, 2, axis=1).astype(np.float32)  # [N, 8]

    X_train, X_test, y_train, y_test = train_test_split(
        X8, y, test_size=0.2, stratify=y, random_state=seed
    )
    return X_train, X_test, y_train, y_test


def rate_encode(features, n_steps=N_STEPS, generator=None):
    """Rate-code a feature batch into Bernoulli spike trains.

    Args:
        features: tensor [batch, N_INPUTS] of values in [0, 1].
        n_steps: number of timesteps.
        generator: optional torch.Generator for reproducible sampling.

    Returns:
        spike tensor of shape [n_steps, batch, N_INPUTS] of 0/1 floats.
    """
    probs = features.unsqueeze(0).expand(n_steps, *features.shape)  # [T,B,8]
    return torch.bernoulli(probs, generator=generator)
