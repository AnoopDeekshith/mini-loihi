"""Phase 1: snnTorch training.

Trains an 8->4->2 Leaky Integrate-and-Fire (LIF) spiking neural network on the
Iris dataset. The trained weights, leak factor (beta), and threshold are later
exported to Q8.8 fixed-point hex files for the Verilog hardware.

TODO: implement model definition, training loop, and checkpoint saving.
"""
