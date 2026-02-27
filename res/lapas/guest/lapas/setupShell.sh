#!/bin/bash

if [ -f "/.lapasUser" ]; then
	export PS1="\[\e[1;37m\]USER\[\e[0m\] \u@\h:\w$ ";
else
	export PS1="\[\e[1;37m\]ADMIN\[\e[0m\] \u@\h:\w$ ";
fi
