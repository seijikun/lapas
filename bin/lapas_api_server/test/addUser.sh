#!/bin/bash

if [ "$1" == "lapas" ]; then
	1>&2 echo "User already exists!";
	exit 1;
fi

1>&2 echo "User added";
exit 0;
