#!/usr/bin/env python3

import os
import sys
import subprocess
import json

## execute a JSON configuration
def executeConfig(cellibpath, shellScriptName, dbpath, subdir, config):
    for fileName in config["files"]:
        hdlsrc = os.path.join(subdir, fileName)
        filewithoutext, file_extension = os.path.splitext(fileName)
        datfile = open(os.path.join(dbpath, filewithoutext + ".dat"), "wt")
        print("  Running HDL file " + fileName)
        retval = subprocess.check_call([os.path.abspath("./scripts/"+shellScriptName+".sh"), os.path.abspath("./" +hdlsrc), celllibpath],
                                cwd=os.path.abspath(subdir),
                                stdout=datfile,
                                stderr=sys.stderr
                                )
        datfile.close()
    return

##########################################################################################
## MAIN PROGRAM STARTS HERE
##########################################################################################

# Check the number of arguments to provide help, if needed.
if (len(sys.argv) < 3):
    print("Usage: database_make <mode> <dir1> .. <dirN>")
    sys.exit(1)

shellScriptName = sys.argv[1]
dbpath = os.path.abspath("./database/"+shellScriptName)
celllibpath = os.path.abspath("./celllibs")

os.system("rm -rf "+dbpath)
os.system("mkdir -p "+dbpath)

# call all generate.py scripts
for dir in sys.argv[2:]:
    for subdir, dirs, files in os.walk(dir):
        for file in files:
            if (file == "generate.py"):
                script = os.path.join(subdir, file)
                print("Executing " + script)
                retval = subprocess.check_call(["python3","generate.py"], 
                                               cwd=os.path.abspath(subdir),
                                               stdout=sys.stdout,
                                               stderr=sys.stderr
                                               )

# execute all .v or .vhdl scripts specified in the config.json file
# or if there is no config.json, simply walk the directory.
dir = sys.argv[2]
queue = [ dir ]
print("Processing directory: " + dir)
while queue:
    subdir = queue.pop()
    listdir = os.listdir(subdir)
    # Do not enter git repositories
    if '.git' in listdir: continue
    for item in listdir:
        path = os.path.join(subdir, item)
        if os.path.isdir(path):
            queue.append(path)
        elif os.path.isfile(path):
            # check if there is a config.json file
            if item == 'config.json':
                print("  Running config file: " + item)
                with open(path, 'r') as configFile:
                    try:
                        config = json.load(configFile)
                        executeConfig(celllibpath, shellScriptName, dbpath, subdir, config)
                    except ValueError as error:
                        print("  --- ERROR PARSING CONFIG.JSON ---")
                        pass
            if (item.endswith(".v")):
                # skip all files that end in _tb.v as they are testbench files
                # containing unsynthesizable code
                if (item.endswith("_tb.v")):
                    print("  Skipping Verilog testbench file " + item)
                    continue
                # skip any netlist files that might have been produced in
                # previous runs
                if (item.endswith("_netlist.v")):
                    print("  Skipping Verilog netlist file " + item)
                    continue
                verilogsrc = os.path.join(subdir, item)
                filewithoutext, file_extension = os.path.splitext(item)
                datfile = open(os.path.join(dbpath, filewithoutext + ".dat"), "wt")
                print("  Running Verilog file " + item)
                retval = subprocess.check_call([os.path.abspath("./scripts/"+shellScriptName+".sh"), os.path.abspath("./" +verilogsrc), celllibpath],
                                            cwd=os.path.abspath(subdir),
                                            stdout=datfile,
                                            stderr=sys.stderr
                                            )
                datfile.close()
            # diego: Sepparating SV for consistency [?]
            if (item.endswith(".sv")):
                if (item.endswith("_tb.sv")):
                    print("  Skipping SystemVerilog testbench file " + item)
                    continue
                systemverilogsrc = os.path.join(subdir, item)
                filewithoutext, file_extension = os.path.splitext(item)
                datfile = open(os.path.join(dbpath, filewithoutext + ".dat"), "wt")
                print("  Running SystemVerilog file " + item)
                retval = subprocess.check_call([os.path.abspath("./scripts/"+shellScriptName+".sh"), os.path.abspath("./" +systemverilogsrc), celllibpath],
                                               cwd=os.path.abspath(subdir),
                                               stdout=datfile,
                                               stderr=sys.stderr
                )
                datfile.close()

            if (item.endswith(".vhdl")):
                # diego: VHDL broken, reading testvector files
                if (item.endswith("_tb.vhdl")):
                    print("  Skipping VHDL testvector file " + item)
                    continue
                vhdlsrc = os.path.join(subdir, item)
                filewithoutext, file_extension = os.path.splitext(item)
                datfile = open(os.path.join(dbpath, filewithoutext + ".dat"), "wt")
                print("  Running VHDL file " + item)
                retval = subprocess.check_call([os.path.abspath("./scripts/"+shellScriptName+".sh"),os.path.abspath("./" +vhdlsrc), celllibpath],
                                            cwd=os.path.abspath(subdir),
                                            stdout=datfile,
                                            stderr=sys.stderr
                                            )
                datfile.close()
