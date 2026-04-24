#!/usr/bin/env python3
"""
Local test script for the unbound-docker image.
Tests that the image builds and the configuration is valid.
"""

import subprocess
import sys
import time

IMAGE = "unbound-custom:test"
CONFIG_PATH = "/etc/unbound/unbound.conf"


def run(cmd, check=True):
    """Run a shell command."""
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if check and result.returncode != 0:
        print(f"❌ Command failed: {cmd}")
        print(result.stderr)
        sys.exit(1)
    return result


def main():
    print("=" * 60)
    print("Testing unbound-docker image")
    print("=" * 60)

    # Step 1: Build
    print("\n[1/3] Building Docker image...")
    run(f"docker build -t {IMAGE} .", check=True)
    print("✅ Build complete")

    # Step 2: Validate config syntax
    print("\n[2/3] Validating Unbound configuration...")
    result = run(
        f"docker run --rm {IMAGE} unbound-checkconf -c {CONFIG_PATH}",
        check=True
    )
    print("✅ Configuration valid")

    # Step 3: Test that Unbound starts
    print("\n[3/3] Testing container startup...")
    container_id = subprocess.check_output(
        f"docker run -d {IMAGE}",
        shell=True, text=True
    ).strip()
    print(f"   Container started: {container_id[:12]}")

    # Wait for startup
    for i in range(10):
        time.sleep(1)
        status = subprocess.run(
            f"docker inspect -f '{{{{.State.Running}}}}' {container_id}",
            shell=True, capture_output=True, text=True
        )
        if status.stdout.strip() == "true":
            print(f"✅ Container running after {i+1}s")
            break
    else:
        print("❌ Container failed to start")
        logs = subprocess.check_output(f"docker logs {container_id}", shell=True, text=True)
        print(logs)
        subprocess.run(f"docker rm -f {container_id}", shell=True)
        sys.exit(1)

    # Verify port is listening
    port_check = subprocess.run(
        f"docker exec {container_id} ss -tuln | grep :53",
        shell=True, capture_output=True, text=True
    )
    if port_check.returncode == 0:
        print("✅ Port 53 is listening")
    else:
        print("⚠️  Port 53 not yet listening (may take longer)")

    # Cleanup
    subprocess.run(f"docker stop {container_id} >/dev/null 2>&1", shell=True)
    subprocess.run(f"docker rm {container_id} >/dev/null 2>&1", shell=True)
    print("✅ Container cleaned up")

    print("\n" + "=" * 60)
    print("All tests passed!")
    print("=" * 60)


if __name__ == "__main__":
    main()
