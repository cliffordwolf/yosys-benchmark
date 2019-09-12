#!/usr/bin/env python3

import sys
import re
import os
import json
import argparse
import logging
logging.basicConfig(stream=sys.stdout, level=logging.DEBUG)

# Makefile dirs
vivado_makefile='vivado_min_period/vivado-2018.3'
yosys_abc9_makefile='vivado_min_period/yosys-master-abc9/'

def execute_command(cmd):
    process=os.system(cmd)
    if (process != 0):
        logging.error("An error occurred while running: {}".format(cmd))

def execute_json(data):
    """
    This function parses a JSON file
    to get the information of tool for synthesis (yosys, vivado, ise)
    directives and possibly custom flow (TODO)
    """
    with open (data, 'r') as f:
        recipeFile = json.load(f)

        for tool in recipeFile:
            logging.info("Tool selected for running is: {}".format(tool['Tool']))

        for directive in recipeFile:
            logging.info("Directive to perform benchmark is: {}".format(directive["Directive"]))

        for items in range(len(recipeFile)):
            command=('make -j$(nproc) DIRECTIVE={} DIR={}'.format(recipeFile[items]["Directive"], recipeFile[items]["Report"]))
            if (recipeFile[items]["Tool"] == "vivado"):
                logging.info("Moving to Vivado directory to store results")
                os.chdir(vivado_makefile)
                logging.info("Executing Vivado Makefile")
                execute_command(command)
                os.chdir(sys.path[0])
            elif (recipeFile[items]["Tool"] == "yosys"):
                logging.info("Moving to Yosys directory to store results")
                os.chdir(yosys_abc9_makefile)
                logging.info("Executing Yosys Makefile")
                execute_command(command)
                os.chdir(sys.path[0])
            else:
                logging.warning("No process executed. Review the JSON recipe file")


""" 
Main
"""
if __name__=="__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--recipe', nargs=1,
                        help="Recipe in JSON format for Benchmarks",
                        type=argparse.FileType('r'))
    arguments=parser.parse_args()
    execute_json(arguments.recipe[0].name)

