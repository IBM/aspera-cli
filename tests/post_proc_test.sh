#!/bin/bash

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

echo ">>>>>>>>>>>>>>>>>POSTPROC SCRIPT BEGIN"
pwd
env|grep '^faspex'
echo "Processing 10 seconds..."
sleep 10
echo ">>>>>>>>>>>>>>>>>POSTPROC SCRIPT END"
exit 1
