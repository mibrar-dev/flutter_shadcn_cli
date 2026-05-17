#!/bin/bash
cd "$(dirname "$0")"

echo "Running Flutter Shadcn CLI Tests..."
echo "===================================="
echo ""

echo "1. Running version_manager_test.dart..."
dart test test/version_manager_test.dart

echo ""
echo "2. Running command_matrix_test.dart..."
dart test test/command_matrix_test.dart

echo ""
echo "3. Running all tests..."
dart test

echo ""
echo "===================================="
echo "Tests completed!"
