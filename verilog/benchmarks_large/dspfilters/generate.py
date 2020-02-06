#!/usr/bin/env python3

import urllib.request
urllib.request.urlretrieve('https://raw.githubusercontent.com/ZipCPU/dspfilters/75756b71d162ca621d6905224d2c836f45efa425/rtl/fastfir.v', 'fastfir.vh')
urllib.request.urlretrieve('https://raw.githubusercontent.com/ZipCPU/dspfilters/75756b71d162ca621d6905224d2c836f45efa425/rtl/slowfil.v', 'slowfil.vh')
urllib.request.urlretrieve('https://raw.githubusercontent.com/ZipCPU/dspfilters/75756b71d162ca621d6905224d2c836f45efa425/rtl/firtap.v', 'firtap.vh')
