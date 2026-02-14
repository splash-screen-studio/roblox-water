#!/usr/bin/env python3

import os
import sys
import subprocess
from dotenv import load_dotenv

load_dotenv()

subprocess.call(
    ['rbxcloud'] +
    sys.argv[1:] +
    [
        '--pretty',
        '--universe-id',
        os.getenv('RBXCLOUD_UNIVERSE_ID'),
        '--place-id',
        os.getenv('RBXCLOUD_PLACE_ID'),
    ]
)
