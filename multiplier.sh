#!/bin/sh

print_help() {
	# Print help text.
	printf 'Usage: %s (-parameter1 -parameter2) [input_file] --output [output_file]\n\n' "${0##*/}"
	echo 'This program automatically adds ES:CE maintenance and operating costs to ships/outfits definitions, calculated from the original cost.'
	echo
	echo 'Parameters:'
	echo '  -m, --multiplier            Sets multiplier for maintenance/operating costs. Assumes multiplier of 1 (standard human gear) if not set.'
	echo '  -f, --force                 Overwrite output file if it exists'
	echo '  -h, --help                  Display help text and exit'
	echo '  -o <file>, --output <file>  Output to file <file>'
}

set_output() {
	# If an output file was already specified:
	if [ x"$output"x != xx ]; then
		# Error out.
		printf '%s: error: Multiple output files specified\n' "${0##*/}" >&2
		return 1
	fi
	# Set the output.
	output="x$1"
}

process_file() {
	# Read the input line-by-line.
	while IFS= read line; do
		# Match the line against the required format.
		case "$line" in
			# Exclude lines that have non-space-characters before the "cost".
			*[![:space:]]*\"cost\"\ *) :;;
			# Exclude lines that don't have an integer after the "cost". 
			*\"cost\"\ *[!0-9]*) :;;
			# Match lines that contain '"cost" '.
			*\"cost\"\ *)
				# Get the leading spaces from the line.
				space="${line%%[![:space:]]*}"
				# Remove the leading space + '"cost" ' from the line, store
				# result in $cost.
				# Ignore the #}', Mousepad's syntax highlighting derped.
				cost="${line#$space\"cost\" }" #}"
				# Multiply $cost by $multiplier and divide by 100.
				cost="$(printf '(%s)*(%s)/100\n' "$cost" "$multiplier" | bc -l)"
				# Calculate two thirds of $cost, round to the closest integer,
				# store result in $operating_costs.
				operating_costs="$(printf 'a=(%s)*2/3;scale=0;(a+.5)/1\n' \
					"$cost" | bc -l)"
				# Calculate $cost - $operating_costs, round to the closest
				# integer, store result in $maintentance_costs.
				maintentance_costs="$(printf 'a=(%s)-(%s);scale=0;(a+.5)/1\n' \
					"$cost" "$operating_costs" | bc -l)"
				# Print the original cost line, operating costs and maintenance costs with the original
				# indentation.
				printf '%s\n%s"operating costs" %i\n%s"maintentance costs" %i\n' \
					"$line" "$space" "$operating_costs" "$space" "$maintentance_costs"
				# Skip the remainder of the while loop and continue with the
				# next iteration.
				continue;;
		esac
		# If there was no match, just print the line.
		printf '%s\n' "$line"
	done
}

main() {
	# Set up initial values for options.
	help=
	output=
	force_write=
	multiplier=1

	# Process arguments.
	n=0
	while [ $# -gt $n ]; do
		case "$1" in
			-f|--force)
				# Enable overwriting of the output file.
				force_write=true
				;;
			-h|--help)
				# Enable displaying of the help text after argument processing.
				help=true
				;;
			-m|--multiplier)
				# If there is no next argument:
				if [ $(($#-$n)) -lt 2 ]; then
					# Error out.
					printf '%s: error: %s option requires an argument\n' \
						"${0##*/}" "$1" >&2
					return 1
				fi
				# Set the multiplier.
				multiplier="$(printf '%s\n' "$2" | bc -l 2>/dev/null)"
				# If the argument could not be parsed by bc:
				if [ x"$multiplier"x = xx ]; then
					# Error out.
					printf '%s: error: Invalid argument for option %s\n' \
						"${0##*/}" "$1" >&2
					return 1
				fi
				shift;;
			-o|--output)
				# If there is no next argument:
				if [ $(($#-$n)) -lt 2 ]; then
					# Error out.
					printf '%s: error: %s option requires an argument\n' \
						"${0##*/}" "$1" >&2
					return 1
				fi
				# Set the output file.
				set_output "$2" || return
				shift;;
			-o*)
				# Set the output file.
				set_output "${1#-o}" || return
				;;
			--output=*)
				# Set the output file.
				set_output "${1#--output=}" || return
				;;
			--)
				# End of options.
				shift
				# Put the files back in the original order.
				while [ $n -lt $# ]; do
					set -- "$@" "$1"
					n=$((n+1))
					shift
				done
				# Break out of loop
				break;;
			-)
				# Unrecognized option: Print error and help text, then exit
				# with error.
				printf '%s: error: Unrecognized option: %s\n' "${0##*/}" "$1" \
					>&2
				print_help
				return 1;;
			*)
				# File argument: Put it at the end of the argument list.
				set -- "$@" "$1"
				n=$((n+1))
				;;
		esac
		# Shift out the argument.
		shift
	done
	unset n
	
	# If --help was specified:
	if [ x"$help"x = x'true'x ]; then
		# Print help text and exit.
		print_help
		return
	fi
	
	# If an output file was specified:
	if [ x"$output"x != xx ]; then
		# If $force_write is not enabled and the output file exists:
		if [ x"$force_write"x != x'true'x ] && [ -e "${output#x}" ]; then
			# Error out.
			printf '%s: error: Output file exists, pass -f to overwrite\n' \
				"${0##*/}" >&2
			return 1
		fi
		# Redirect stdout to the output file.
		exec > "${output#x}" || return
	fi
	
	# If no input file was specified:
	if [ $# -le 0 ]; then
		# Process stdin.
		process_file || return
	# Otherwise:
	else
		# Process all input files.
		for input; do
			< "$input" process_file || return
		done
	fi
}

main ${1+"$@"}
