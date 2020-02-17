# Yosys-bench

This is a collection of Verilog designs of different type and size, used as benchmarks in Yosys development.

Create a PR if you think you have an interesting benchmark.


### benchmarks_small

This directory contains small (mostly synthetic) benchmarks that can be used
to analyse and compare the performance of the tools in specific situations.


### benchmarks_large

This directory contains larger "real-world" designs. They can be used for
estimating the overall performance of the tools.

# Running the benchmarks

Benchmarks are processed by the ```./scripts/database_make.py``` Python3 script. The script performs the following steps:

* It traverses the given directories and executes the `generate.py` Python script, if there is one. These scripts generate Verilog or VHDL files for some testbenches. 
* It checks for a `config.json` file. If there is one, it loads the configuration and reads which HDL files it should use for the testbench.
* If there wasn't a `config.json` file, it simply uses all the `.v` and `.vhdl` files it can find for the testbench.

example:
```./scripts/database_make.py yosys-ice40-lutcount <directory1> <directory2>```

Each benchmark produces an entry in the `./database` directory. Running `./scripts/database_html.sh` will generate a .html file with the results in the `./database` directory.

# Adding benchmarks
To add a benchmark, simply create a directory in the `benchmarks_small` or `benchmarks_large` directory, optionally supply a `generate.py` and/or `config.json` and add your HDL files.

Please also add a `README.md` file to your benchmark so others know what it is you are benchmarking.

# The `config.json` file
The `config.json` file lists the HDL files that you want to benchmark. Each file will be benchmarked separately.

Example:

```
{
    "files": 
    [
        "sddac.v", "sddac2.v"
    ]
}
```

# The _benchmarks.py_ script

## Setup
The `litex` benchmarks needs submodules to be cloned as well.
Inside your clone directory:
``` 
git submodule update --init --recursive
```

## Execution

The __benchmarks.py__ script reads a JSON file on which the _Tool_, _Directive_, _Report_ and _Prepend_ fields are defined. The script passed all that information to _vivado_min_period.sh_. An example of such JSON file is as follows:
```json
{
  "Large": [
    {
      "Tool": "yosys",
      "Directive": "Default",
      "Report": "yosys_large_default",
      "YosysArgs": "-abc9",
      "Prepend": "scratchpad -set abc9.if.C 16"
    },
    {
      "Tool": "vivado",
      "Directive": "Default",
      "Report": "vivado_large_default",
      "YosysArgs": "-abc9"
    }
  ],
  "Small": [
    {
      "Tool": "vivado",
      "Directive": "Default",
      "Report": "vivado_small_default",
      "YosysArgs": "-abc9"
    },
    {
      "Tool": "yosys",
      "Directive": "Default",
      "Report": "yosys_small_default",
      "YosysArgs": "-abc9"
    }
  ]
}
```
*Note:* There are two keys in the JSON file, one for _Small_ designs and other for _Large_ ones. With this mechanism, both benchmarks (or just one type) can be run and stored in different directories. 

* Let JSON file name = benchmarks.json, the script is called as follows:
```bash
$ ./benchmarks.py --recipe benchmarks.json
```

* In this example, two directories will be created under _vivado_min_period/vivado-2018.3/_ and _vivado_min_period/yosys-master-abc9/_ respectively. These directories will be named as defined in __"Report"__ field of JSON recipe.

* A file called _results_$(DEVICE)_$(DIRECTIVE)_$(DIR).csv_ is generated after script finish. This CSV file contains the information that fills the fields in the spreadsheet reports. 
