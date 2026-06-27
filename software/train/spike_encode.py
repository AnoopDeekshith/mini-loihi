"""Rate coding encoder.

Converts a normalized scalar (or values) into a spike train using rate coding:
each timestep emits a spike with probability proportional to the input value.
A larger x => higher firing probability => denser spike train.

Used in Phase 1 to turn continuous Iris features into spikes for the SNN.
"""

import torch
import matplotlib

matplotlib.use("Agg")  # headless backend, safe for CI / no display
import matplotlib.pyplot as plt


def rate_encode(x, n_steps, max_rate=100):
    """Rate-code a normalized value into a spike train.

    Args:
        x: normalized float in [0, 1].
        n_steps: number of timesteps in the output spike train.
        max_rate: max firing rate as a percentage (100 => fire every step
            when x == 1.0).

    Returns:
        torch.Tensor of shape [n_steps] containing 0s and 1s (float).
    """
    prob = x * max_rate / 100.0
    prob = max(0.0, min(1.0, float(prob)))  # clamp to a valid probability
    probs = torch.full((n_steps,), prob)
    spikes = torch.bernoulli(probs)
    return spikes


if __name__ == "__main__":
    torch.manual_seed(0)  # reproducible spike trains for the demo

    n_steps = 50
    values = [0.2, 0.5, 0.9]

    trains = {}
    for x in values:
        spikes = rate_encode(x, n_steps)
        trains[x] = spikes
        n_fired = int(spikes.sum().item())
        print(f"x={x:.1f}  fired {n_fired}/{n_steps} steps "
              f"(~{100 * n_fired / n_steps:.0f}%)")
        print(f"  spikes: {spikes.int().tolist()}")

    # --- Spike raster plot ---
    fig, ax = plt.subplots(figsize=(10, 3))
    for row, x in enumerate(values):
        spike_steps = torch.nonzero(trains[x]).squeeze(1).tolist()
        ax.scatter(spike_steps, [row] * len(spike_steps),
                   marker="|", s=400, color="black")
    ax.set_yticks(range(len(values)))
    ax.set_yticklabels([f"x={x}" for x in values])
    ax.set_xlabel("timestep")
    ax.set_title(f"Rate-coded spike raster ({n_steps} steps)")
    ax.set_xlim(-1, n_steps)
    fig.tight_layout()

    out_path = "docs/spike_raster.png"
    fig.savefig(out_path, dpi=120)
    print(f"\nSaved spike raster to {out_path}")
