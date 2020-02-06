#!/usr/bin/env python3

import subprocess
import urllib.request
urllib.request.urlretrieve('https://raw.githubusercontent.com/enjoy-digital/litex/33d7cc5fc81cc7785be217f64d756db6092aeff6/litex/soc/cores/cpu/lm32/verilog/config/lm32_config.v', 'lm32/rtl/lm32_config.v')
