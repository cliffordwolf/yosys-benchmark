#!/usr/bin/env python3

import sys
import re
import os
import json
import argparse
import logging
logging.basicConfig(stream=sys.stdout, level=logging.DEBUG)

# Makefile dirs
ise_makefile='ise_min_period/ise-14.7'
yosys_s6_makefile='ise_min_period/yosys-master-abc9'
vivado_makefile='vivado_min_period/vivado-2018.3'
yosys_abc9_makefile='vivado_min_period/yosys-master-abc9/'

def execute_command(cmd):
    process=os.system(cmd)
    if (process != 0):
        logging.error("An error occurred while running: {}".format(cmd))

def run_main(runtype, **recipeFile):
    command=('{} make -j$(nproc) DIRECTIVE={} DIR={}'.format(runtype, recipeFile['Directive'], recipeFile['Report']))
    if (recipeFile["Tool"] == "vivado"):
        logging.info("Moving to Vivado directory to store results. Executing command {}".format(command))
        os.chdir(vivado_makefile)
        execute_command(command+"&")
        os.chdir(sys.path[0])
    elif (recipeFile["Tool"] == "yosys"):
        command=(command+' YSARGS="{}"'.format(recipeFile["YosysArgs"]))
        logging.info("Moving to Yosys directory to store results. Executing command {}".format(command))
        os.chdir(yosys_abc9_makefile)
        execute_command(command+"&")
        os.chdir(sys.path[0])
    elif (recipeFile["Tool"] == "ise"):
        logging.info("Moving to ISE directory to store results. Executing command {}".format(command))
        os.chdir(ise_makefile)
        execute_command(command+"&")
        os.chdir(sys.path[0])
    elif (recipeFile["Tool"] == "yosys_s6"):
        command=(command+' YSARGS="{}"'.format(recipeFile["YosysArgs"]))
        logging.info("Moving to Yosys S6 directory to store results. Executing command {}".format(command))
        os.chdir(yosys_s6_makefile)
        execute_command(command+"&")
        os.chdir(sys.path[0])
    else:
        logging.warning("No process executed. Review the JSON recipe file")
 
def execute_json2(data):
    """
    This function parses a JSON file
    to get the information of tool for synthesis (yosys, vivado, ise),
    directives and possibly custom flow (TODO)
    """
    with open (data, 'r') as f:
        recipeFile = json.load(f)
        logging.info("Keys are {}".format(recipeFile.keys()))

        for key in recipeFile.keys():
            logging.info("Key is {}".format(key))
            if key in ('Large', 'Small'):
                runtype=("{}=1".format(key.upper()))
                for values in recipeFile[key]:
                    logging.info("Tool selected for running is: {}".format(values['Tool']))
                    logging.info("Directive to perform benchmark is: {}".format(values['Directive']))
                    logging.info("Type of benchmark is: {}".format(key))
                    run_main(runtype, **values)
            else:
                raise Exception('Value selected for benchmark type is wrong: {}. It shoule be either Small or Large. Please review the JSON file'.format(key))

""" 
Main
"""
if __name__=="__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--recipe', nargs=1,
                        help="Recipe in JSON format for Benchmarks",
                        type=argparse.FileType('r'))
    arguments=parser.parse_args()
    execute_json2(arguments.recipe[0].name)


