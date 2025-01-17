#!/usr/bin/env bash

###################################################
#
# file: myjstat.sh
#
# @Author:  Iacovos G. Kolokasis
# @Version: 19-01-2021
# @email:   kolokasis@ics.forth.gr
#
# @brief    This script tracks the memory usage 
###################################################

# Output file name
OUTPUT=$1        

# Loop until the count of "Main" in jps output is 1
while [ $(jps | grep -c "MultiTenantEvaluateQueries") -ne 1 ]; do
#while [ $(jps | grep -c "Main") -ne 1 ]; do
  # No op
  :
done

while true; do
    free -m >> "${OUTPUT}"
    sleep 1
done
