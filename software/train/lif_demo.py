"""Phase 0 — First LIF spike.

Drives a single snnTorch Leaky Integrate-and-Fire neuron with a few current
pulses and observes the membrane potential integrating, crossing threshold, and
resetting. This is the software-side "hello world" the Verilog lif_core will
later reproduce in Q8.8 fixed point.
"""

import torch
import snntorch as snn
import matplotlib

matplotlib.use("Agg")  # headless backend, safe for CI / no display
import matplotlib.pyplot as plt


def main():
    n_steps = 25
    beta = 0.9

    # Single LIF neuron. Default threshold in snn.Leaky is 1.0.
    lif = snn.Leaky(beta=beta)
    mem = lif.init_leaky()  # initial membrane potential (0.0)

    # Input current: pulses of 0.5 at selected timesteps, 0 otherwise.
    pulse_steps = {2, 5, 8, 12, 18}
    pulse_amp = 0.5

    v_rec = []
    spk_rec = []
    i_rec = []

    print(f"{'t':>3} | {'I_syn':>6} | {'V_mem':>7} | {'spike':>5}")
    print("-" * 32)

    for t in range(n_steps):
        i_syn = torch.tensor(pulse_amp if t in pulse_steps else 0.0)
        spk, mem = lif(i_syn, mem)

        i_val = float(i_syn)
        v_val = float(mem)
        s_val = int(spk)

        i_rec.append(i_val)
        v_rec.append(v_val)
        spk_rec.append(s_val)

        print(f"{t:>3} | {i_val:>6.3f} | {v_val:>7.4f} | {s_val:>5}")

    n_spikes = sum(spk_rec)

    # --- Plot membrane potential with spike markers ---
    fig, ax = plt.subplots(figsize=(10, 4))
    steps = list(range(n_steps))
    ax.plot(steps, v_rec, marker="o", color="tab:blue", label="V_mem")
    ax.axhline(1.0, color="tab:red", linestyle="--", label="threshold (θ=1.0)")

    spike_steps = [t for t, s in enumerate(spk_rec) if s]
    if spike_steps:
        ax.scatter(spike_steps, [1.05] * len(spike_steps),
                   marker="*", s=200, color="tab:orange", zorder=5,
                   label="spike")

    ax.set_xlabel("timestep")
    ax.set_ylabel("membrane potential")
    ax.set_title(f"LIF neuron (β={beta}) — {n_spikes} spikes / {n_steps} steps")
    ax.legend(loc="upper right")
    fig.tight_layout()

    out_path = "docs/lif_demo.png"
    fig.savefig(out_path, dpi=120)
    print(f"\nSaved membrane-potential plot to {out_path}")

    print(f"LIF neuron fired {n_spikes} times over {n_steps} timesteps")


if __name__ == "__main__":
    main()
