#!/usr/bin/env python3

from common import gen_muladd

ARange = ['16','32s']
BRange = ['8','16s']
CRange = ['32','40s']

if __name__ == "__main__":
    gen_muladd(ARange, BRange, CRange)
