#!/usr/bin/env python3

from common import gen_macc

ARange = ['16','16s','24','24s','32','32s']
BRange = ['2','2s','4','4s','8','8s','16','16s']

if __name__ == "__main__":
    gen_macc(ARange, BRange)
