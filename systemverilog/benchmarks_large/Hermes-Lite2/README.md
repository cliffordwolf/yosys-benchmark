Hermes-Lite 2.x
===============

See the main [Hermes-Lite Web Page](http://www.hermeslite.com) for the latest links and details.

This is a work in progress to create a low-cost software defined amateur radio HF transceiver based on a [broadband modem chip](http://www.analog.com/en/broadband-products/broadband-codecs/ad9866/products/product.html) and the [Hermes SDR](http://openhpsdr.org/wiki/index.php?title=HERMES) project.

## Notes
In ice40, this error is shown after some minutes of running:
```bash
ERROR: ABC: execution of command "$SYMBIOTICEDA_HOME/symbiotic-20190724A-symbiotic/lib/yosys-abc -s -f /tmp/yosys-abc-HMSIdK/abc.script 2>&1" failed: return code -1.
```
Running manually, it doesn't show any error:
```bash
➜  yosys-bench-sv git:(svdevel) ✗ $SYMBIOTICEDA_HOME/symbiotic-20190724A-symbiotic/lib/yosys-abc -s -f /tmp/yosys-abc-HMSIdK/abc.script
ABC command line: "source /tmp/yosys-abc-HMSIdK/abc.script".

+ read_blif /tmp/yosys-abc-HMSIdK/input.blif 
+ read_lut /tmp/yosys-abc-HMSIdK/lutdefs.txt 
+ strash 
+ ifraig 
+ scorr 
Warning: The network is combinational (run "fraig" or "fraig_sweep").
+ dc2 
+ dretime 
+ retime 
+ strash 
+ dch -f 
+ if 
+ mfs2 
+ lutpack -S 1 
+ dress 
Total number of equiv classes                =   44341.
Participating nodes from both networks       =   90404.
Participating nodes from the first network   =   44492. (  95.34 % of nodes)
Participating nodes from the second network  =   45912. (  98.38 % of nodes)
Node pairs (any polarity)                    =   44492. (  95.34 % of names can be moved)
Node pairs (same polarity)                   =   33178. (  71.10 % of names can be moved)
Total runtime =     4.52 sec
+ write_blif /tmp/yosys-abc-HMSIdK/output.blif 
```

** This error is not present when synthesizing for other families**
