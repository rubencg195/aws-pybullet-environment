#!/usr/bin/env bash
# Sourced by run-acceptance.sh and run-pybullet-s3-sim-test.sh after AWS=(aws --profile ...) is set.
# Requires: INSTANCE_ID, REGION, AWS (array), optional EXPECT_NAME_SUFFIX default "-pybullet"
# Exits 1 if the instance is missing, terminated, or not running.
ec2_host_precheck() {
  local iid="${INSTANCE_ID:?}"
  local region="${REGION:?}"
  local expect_suffix="${EXPECT_NAME_SUFFIX:--pybullet}"

  local state name
  state="$("${AWS[@]}" ec2 describe-instances \
    --instance-ids "${iid}" \
    --region "${region}" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text 2>/dev/null || true)"
  name="$("${AWS[@]}" ec2 describe-instances \
    --instance-ids "${iid}" \
    --region "${region}" \
    --query 'Reservations[0].Instances[0].Tags[?Key==`Name`].Value | [0]' \
    --output text 2>/dev/null || true)"

  if [[ -z "${state}" || "${state}" == "None" ]]; then
    echo "EC2: instance ${iid} not found in ${region} (wrong account/region/id?)." >&2
    echo "If you removed aws_instance from OpenTofu state, 'tofu output pybullet_host_instance_id' can still show an old id — run 'tofu apply' to recreate the host." >&2
    return 1
  fi

  if [[ "${state}" == "terminated" ]] || [[ "${state}" == "shutting-down" ]]; then
    echo "EC2: instance ${iid} is ${state} (not 'stopped'). Terminated instances cannot be started." >&2
    echo "OpenTofu outputs may still list this id even when the resource is gone from state — run 'cd infrastructure && tofu apply -auto-approve' to launch a new host." >&2
    return 1
  fi

  if [[ "${state}" != "running" ]]; then
    echo "EC2: instance ${iid} is '${state}' (need 'running'). Start it in the EC2 console or run 'tofu apply'." >&2
    return 1
  fi

  if [[ -n "${name}" && "${name}" != "None" && "${name}" == *packer-builder* ]]; then
    echo "EC2: Name tag is '${name}' — that is the temporary Packer builder, not the PyBullet DCV host (expected *${expect_suffix})." >&2
    echo "Use the instance tagged Name=<project>-pybullet, or fix OpenTofu state/outputs." >&2
    return 1
  fi

  echo "EC2: ${iid} running (Name=${name:-unknown})"
  return 0
}
