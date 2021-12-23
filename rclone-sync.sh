#!/bin/sh

healthchecks_io_start() {
  local url

  if [ ! -z "${HEALTHCHECKS_IO_URL}" ]
  then
    url=${HEALTHCHECKS_IO_URL}/start
    echo "INFO: Sending helatchecks.io start signal to '${url}'"

    wget ${url} -O /dev/null
  fi
}

healthchecks_io_end() {
  local return_code=$1
  local url

  # Wrap up healthchecks.io call with complete or failure signal
  if [ ! -z "${HEALTHCHECKS_IO_URL}" ]
  then
    if [ "${return_code}" == 0 ]
    then
      url=${HEALTHCHECKS_IO_URL}
      echo "INFO: Sending helatchecks.io complete signal to '${url}'"
    else
      url=${HEALTHCHECKS_IO_URL}/fail
      echo "WARNING: Sending helatchecks.io failure signal to '${url}'"
    fi

    wget ${url} -O /dev/null
  fi
}

is_rclone_running() {
  if [ $(lsof | grep $0 | wc -l | tr -d ' ') -gt 1 ]
  then
    return 0
  else
    return 1
  fi
}

is_remote_exists() {
  local remote=$1

  if [ -z "${remote}" ]
  then
    return_code=1
  else
    CMD="rclone --max-depth 1 lsf ${remote} ${rclone_config_file}"

    echo "INFO: Executing: ${CMD}"
    set +e
    eval ${CMD}
    return_code=$?
    set -e
  fi

  return ${return_code}
}

get_rclone_cmd_opts() {
  # Evaluate any sync options
  if [ ! -z "${SYNC_OPTS_EVAL}" ]
  then
    SYNC_OPTS_EVALUALTED=$(eval echo $SYNC_OPTS_EVAL)
    echo "INFO: Evaluated SYNC_OPTS_EVAL to: ${SYNC_OPTS_EVALUALTED}"
    SYNC_OPTS_ALL="${SYNC_OPTS} ${SYNC_OPTS_EVALUALTED}"
  else
    SYNC_OPTS_ALL="${SYNC_OPTS}"
  fi
}

rclone_cmd_exec() {
  CMD="rclone ${command} '${source}' '${destination}' ${rclone_config_file} ${SYNC_OPTS_ALL}"

  if [ ! -z "$LOG_ENABLED" ]
  then
    d=$(date +%Y_%m_%d-%H_%M_%S)
    LOG_FILE="${log_dir}/rclone-$d.log"
    CMD="${CMD} --log-file=${LOG_FILE} --log-level INFO"
  fi

  echo "INFO: Executing: ${CMD}"
  set +e
  eval ${CMD}
  return_code=$?
  set -e

  return ${return_code}
}

rotate_logs() {
  # Delete logs by user request
  if [ ! -z "${LOG_ROTATE##*[!0-9]*}" ]
  then
    echo "INFO: Removing logs older than ${LOG_ROTATE} day(s)..."
    touch ${log_dir}/tmp.log && find ${log_dir}/*.log -mtime +${LOG_ROTATE} -type f -delete && rm -f ${log_dir}/tmp.log
  fi
}

set -e

command=${RCLONE_CMD}
source=${SYNC_SRC}
destination=${SYNC_DEST:-/data}
pid_file=/var/lib/rclone/rclone-sync.pid
log_dir=/var/log/rclone
rclone_config_file="--config /etc/rclone/rclone.conf"

echo "INFO: Starting sync.sh pid $$ $(date)"

if is_rclone_running
then
  echo "WARNING: A previous rclone instance is still running. Skipping new ${command} command."
else
  echo $$ > ${pid_file}
  echo "INFO: PID file created successfuly: ${pid_file}"

  healthchecks_io_start

  rotate_logs

  rclone_cmd_opts=get_rclone_cmd_opts

  if is_remote_exists ${source}
  then
    echo "INFO: Source directory is not empty and can be processed without clear loss of data"

    rclone_cmd_exec

    return_code=$?
  else
    echo "WARNING: Source directory \"${sorce}\" does not exists. Skipping ${command} command."

    return_code=1
  fi

  healthchecks_io_end ${return_code}

  echo "INFO: Removing PID file"
  rm -f ${pid_file}
fi
