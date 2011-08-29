#
# a framework for spawning processes
#
# Jeffrey Lau
# 2011-08-29
#
# Set default program name
N="${N:-"${0##*/}"}"

# Set default log file
logfile="${logfile:-~/log/spawn-${N}.log}"

# Do you really want me to log debug messages?
wantlog="${wantlog:-'0'}"

# log stuff to a file
function log() {
	if [ "${wantlog}" = '1' ]; then
		stuff="${*}"
		echo "`date "+%a %Y%m%d-%H:%M:%S-%z"`: ${stuff}" >> "${logfile}"
	else
		return 0
	fi
}

# both echo and log
function logcho() {
	stuff="${*}"
	echo "${stuff}"
	log "${stuff}"
}

### Functions
function singlespawn() {
	# extract the app name out for grepping later.
	# Can be a grep regexp.
	# E.g., use `\|' for an `or' match
	local app_name="${1}"
	shift
	# if we're only given one single arg, then treat that also as the command
	local app_cmd="${*:-${app_name}}"
	# local out=`ps aux | \
		# grep "${app_name}" | \
		# grep "${UID}" | \
		# sed -e 's/\s\+/ /g' | \
		# cut -d ' ' -f 11 | \
		# grep "${app_name}" | \
		# grep -v grep`

	log "testing for app: ${app_name}"
	# local out=`ps aux | grep -e "${app_name}" | grep "${UID}" | sed -e 's/\s\+/ /g' | cut -d ' ' -f 11 | grep -e "${app_name}" | grep -v grep`
	local out=`ps aux | grep -e "${app_name}" | grep "${UID}" | sed -e 's/\s\+/ /g' | cut -d ' ' -f 11- | grep -e "${app_name}" | grep -v grep`
	if [ "${out}" = "" ]; then
		# return
		# Otherwise, spawn a trayer process.
		logcho "${N}:  Spawning ${app_name}"'!'
		# local cmd="${app_name} ${app_cmd}"
		local cmd="${app_cmd}"
		log "  \`--> gonna do: ${cmd}"
		echo "${cmd}"
		eval "${cmd}"
	else
		# If there is SOMETHING, then that means
		# there IS a relevant process under our own UID.
		# In which case, we should just do nothing.
		logcho "${N}:  doing nothing, as a \`${app_name}' process already exists."
		logcho "  \`--> out is '${out}'."
	fi

}

# Like singlespawn, but puts the process to the background.
function singlespawnbg() {
	# check to see if we're only given one single arg
	if [ "$#" = 1 ]; then
		singlespawn "${1}" "${1} &"
	else
		# else just add a `&' behind
		singlespawn ${*} "&"
	fi
}
