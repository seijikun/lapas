#!/bin/bash

if [ -f "/.lapasUser" ]; then
        export PS1="USER $PS1";
else
        export PS1="ADMIN $PS1";
fi