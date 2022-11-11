#!/bin/bash

if [ "${root%%:*}" = "misolabel" ]; then
    rootok=1
    return 0
else
    return 1
fi