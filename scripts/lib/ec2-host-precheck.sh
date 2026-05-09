#!/usr/bin/env bash
# Sourced by run-acceptance.sh and run-pybullet-s3-sim-test.sh after AWS=(aws --profile ...) is set.
# Requires: INSTANCE_ID, REGION, AWS (array), optional EXPECT_NAME_SUFFIX default "-pybullet"
# Optional: EC2_START_WAIT_MAX_SEC (default 600) max seconds to wait for running after start.
# Exits 1 if the instance is missing, terminated, or the Packer builder; otherwise ensures running
# (starts if stopped, waits if stopping/pending).

ec2_host_precheck() {
  local iid="${INSTANCE_ID:?}"
  local region="${REGION:?}"
  local expect_suffix="${EXPECT_NAME_SUFFIX:--pybullet}"
  local max_wait="${EC2_START_WAIT_MAX_SEC:-600}"

  _ec2_describe() {
    if ! "${AWS[@]}" ec2 describe-instances \
      --instance-ids "${iid}" \
      --region "${region}" \
      --query 'Reservations[0].Instances[0].[State.Name,Tags[?Key==`Name`].Value | [0]]' \
      --output text 2>/dev/null; then
      return 1
    fi
  }

  local line
  line="$(_ec2_describe)" || true
  if [[ -z "${line}" || "${line}" == "None" ]]; then
    echo "EC2: cannot describe instance ${iid} in ${region} (wrong id, region, or AWS profile?)." >&2
    echo "Stopped instances are still returned by describe-instances; if you see this, the id is invalid or the API call failed." >&2
    echo "Tip: 'tofu output pybullet_host_instance_id' may be stale — run 'tofu refresh' or 'tofu apply'." >&2
    return 1
  fi

  # Two tab-separated fields: State.Name and Name tag (second may be absent or "None").
  local state name
  IFS=$'\t' read -r state name <<< "${line}" || true
  [[ -z "${state}" || "${state}" == "None" ]] && state=""
  [[ "${name}" == "None" ]] && name=""
  if [[ -z "${state}" ]]; then
    echo "EC2: empty state for ${iid} (unexpected describe output: ${line})." >&2
    return 1
  fi

  if [[ -n "${name}" && "${name}" == *packer-builder* ]]; then
    echo "EC2: Name tag is '${name}' — that is the temporary Packer builder, not the PyBullet DCV host (expected *${expect_suffix})." >&2
    echo "Use the instance tagged Name=<project>-pybullet." >&2
    return 1
  fi

  if [[ "${state}" == "terminated" ]] || [[ "${state}" == "shutting-down" ]]; then
    echo "EC2: instance ${iid} is ${state}. Terminated instances cannot be started." >&2
    echo "Run 'cd infrastructure && tofu apply -auto-approve' to create a new host." >&2
    return 1
  fi

  # Wait out "stopping" so we can start cleanly.
  local waited=0
  while [[ "${state}" == "stopping" ]] && [[ "${waited}" -lt "${max_wait}" ]]; do
    echo "EC2: ${iid} is stopping — waiting before start (up to ${max_wait}s)..."
    sleep 10
    waited=$((waited + 10))
    line="$(_ec2_describe)" || true
    IFS=$'\t' read -r state _ <<< "${line}" || true
  done

  if [[ "${state}" == "stopping" ]]; then
    echo "EC2: ${iid} still stopping after ${max_wait}s." >&2
    return 1
  fi

  if [[ "${state}" == "stopped" ]]; then
    echo "EC2: ${iid} is stopped — starting..."
    if ! "${AWS[@]}" ec2 start-instances --instance-ids "${iid}" --region "${region}" >/dev/null; then
      echo "EC2: start-instances failed for ${iid}." >&2
      return 1
    fi
    state="pending"
  fi

  # Already running: return immediately. Avoids a polling loop where a flaky describe could
  # empty state and time out even though the instance never left running.
  if [[ "${state}" == "running" ]]; then
    echo "EC2: ${iid} already running (Name=${name:-unknown})"
    return 0
  fi

  if [[ "${state}" == "pending" ]]; then
    echo "EC2: waiting for ${iid} to reach running (max ${max_wait}s)..."
    waited=0
    while [[ "${waited}" -lt "${max_wait}" ]]; do
      line="$(_ec2_describe)" || true
      IFS=$'\t' read -r state _ <<< "${line}" || true
      if [[ "${state}" == "running" ]]; then
        break
      fi
      if [[ "${state}" == "terminated" ]] || [[ "${state}" == "shutting-down" ]]; then
        echo "EC2: ${iid} entered ${state} while waiting." >&2
        return 1
      fi
      sleep 5
      waited=$((waited + 5))
    done
  fi

  if [[ "${state}" != "running" ]]; then
    echo "EC2: ${iid} is '${state}' after wait (expected running)." >&2
    return 1
  fi

  echo "EC2: ${iid} running (Name=${name:-unknown})"
  return 0
}
