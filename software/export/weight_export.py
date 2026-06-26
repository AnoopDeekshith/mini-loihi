"""Quantize + export trained weights to hex.

Loads the trained snnTorch checkpoint, quantizes each nn.Linear weight matrix to
Q8.8 fixed-point (16-bit, 8 integer / 8 fractional bits), and writes the
hardware memory files:
  - hardware/mem/layer1_weights.hex  (8 -> 4 layer)
  - hardware/mem/layer2_weights.hex  (4 -> 2 layer)

TODO: implement float_to_q8_8(), quantization, and hex file writing.
"""
