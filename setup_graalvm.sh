#!/bin/bash

set -e

# GraalVM version for Java 21
GRAALVM_VERSION="21.0.2"
GRAALVM_JAVA_VERSION="21"

echo "Installing GraalVM Community ${GRAALVM_VERSION} (Java ${GRAALVM_JAVA_VERSION})"
echo "This version supports Quarkus 3.x with Java 21"

# Create a directory for GraalVM
mkdir -p $HOME/graalvm

# Download GraalVM Community 21.0.2 for Java 21
# Note: Using GraalVM Community from GitHub releases
wget -O $HOME/graalvm/graalvm-community-jdk-21_linux-x64_bin.tar.gz \
  https://github.com/graalvm/graalvm-ce-builds/releases/download/jdk-21.0.2/graalvm-community-jdk-21.0.2_linux-x64_bin.tar.gz

# Extract the archive
tar -xzf $HOME/graalvm/graalvm-community-jdk-21_linux-x64_bin.tar.gz -C $HOME/graalvm

# Detect the actual extracted directory name (matches both jdk and openjdk naming)
EXTRACTED_DIR=$(ls -d $HOME/graalvm/graalvm-community-*jdk-21* 2>/dev/null | grep -v "\.tar\.gz" | head -1)

if [ -z "$EXTRACTED_DIR" ]; then
    echo "Error: Could not find extracted GraalVM directory"
    exit 1
fi

echo "GraalVM extracted to: $EXTRACTED_DIR"

# Set environment variables in .bashrc
echo '' >> ~/.bashrc
echo '# GraalVM environment variables (updated for Quarkus compatibility)' >> ~/.bashrc
echo "export GRAALVM_HOME=$EXTRACTED_DIR" >> ~/.bashrc
echo 'export JAVA_HOME=$GRAALVM_HOME' >> ~/.bashrc
echo 'export PATH=$JAVA_HOME/bin:$PATH' >> ~/.bashrc

# Also set for current session
export GRAALVM_HOME=$EXTRACTED_DIR
export JAVA_HOME=$GRAALVM_HOME
export PATH=$JAVA_HOME/bin:$PATH

# Install the native-image tool (if not already included)
if [ -f "$GRAALVM_HOME/bin/gu" ]; then
    echo "Installing native-image tool..."
    $GRAALVM_HOME/bin/gu install native-image || echo "native-image may already be installed"
else
    echo "Note: native-image should be included in GraalVM 23.1+"
fi

# Verify installation
echo ""
echo "=== GraalVM Installation Complete ==="
echo "GraalVM Home: $GRAALVM_HOME"
echo ""
$GRAALVM_HOME/bin/java -version
echo ""
if [ -f "$GRAALVM_HOME/bin/native-image" ]; then
    $GRAALVM_HOME/bin/native-image --version
else
    echo "Warning: native-image not found"
fi
echo ""
echo "Please run 'source ~/.bashrc' or open a new terminal to use GraalVM."
echo ""
echo "To build Quarkus native image with Java 21, run:"
echo "  cd quarkus_cloud_run"
echo "  ./mvnw package -Pnative -DskipTests"
