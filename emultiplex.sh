#!/bin/sh
erlc emultiplex.erl && erl -run emultiplex launch $@