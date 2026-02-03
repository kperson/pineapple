#!/bin/bash
# Helper script to set SystemTests environment variables from Terraform outputs

set -e

echo "🍍 Setting up SystemTests environment variables from Terraform..."
echo ""

# Check if we're in the Build directory
if [ ! -f "main.tf" ]; then
    echo "❌ Error: Run this script from the Build/ directory"
    echo "   cd Build && ./setup-systemtest-env.sh"
    exit 1
fi

# Check if Terraform has been applied
if [ ! -f "terraform.tfstate" ]; then
    echo "❌ Error: No terraform.tfstate found"
    echo "   Run 'terraform apply' first"
    exit 1
fi

# Generate environment variable exports
echo "# SystemTests Environment Variables"
echo "# Generated from Terraform on $(date)"
echo ""

terraform output -raw systemtest_env_vars

echo ""
echo "✅ To use these variables, run:"
echo "   source <(cd Build && ./setup-systemtest-env.sh)"
echo ""
echo "   Or copy-paste the export commands above"
