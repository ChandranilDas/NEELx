#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'python3 -c "import shutil, sys; shutil.rmtree(sys.argv[1])" "$test_dir"' EXIT

swiftc -O -o "$test_dir/session" NEELx/SessionSecurityPolicy.swift tools/session_security_selftest.swift
"$test_dir/session"

swiftc -O -o "$test_dir/liveness" NEELx/Liveness/{LandmarkGeometry,GeometryLiveness,GlareCue,LivenessCues,LivenessScoring,LivenessAnalyzer,NeuralDepthAnalyzer}.swift tools/liveness_selftest.swift
"$test_dir/liveness"
