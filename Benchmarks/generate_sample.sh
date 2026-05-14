#!/bin/bash
set -e

REPO_NAME="SampleProject"
mkdir -p "$REPO_NAME"
cd "$REPO_NAME"

rm -rf .git
git init
git branch -m main

commit_changes() {
    git add .
    git commit -m "$1"
}

echo "public class Database { public init() {}; public func connect() { print(\"Connected\") } }" > Database.swift
echo "public struct User { public let id: String; public let name: String }" > User.swift
commit_changes "feat: Initial core models"

for i in $(seq 2 10); do
    mkdir -p "Module$i"
    for j in $(seq 1 10); do
        FILE="Module$i/NoiseManager${i}_${j}.swift"
        echo "import Foundation" > "$FILE"
        echo "public class NoiseManager${i}_${j} {" >> "$FILE"
        echo "    var db: Database?" >> "$FILE"
        echo "    public init() {}" >> "$FILE"
        
        # Every 3 commits, add a "High Signal" function that uses core types
        if [ $((i % 3)) -eq 0 ] && [ $j -eq 1 ]; then
            echo "    /// Crucial function for commit $i" >> "$FILE"
            echo "    public func processDatabaseRecords(db: Database, user: User) {" >> "$FILE"
            echo "        print(\"Processing for \\(user.name)\")" >> "$FILE"
            echo "        db.connect()" >> "$FILE"
            echo "    }" >> "$FILE"
        fi

        for k in $(seq 1 50); do
            # Occasionally use core types in noisy functions
            if [ $((k % 10)) -eq 0 ]; then
                echo "    public func legacyOp${k}(user: User) { print(user.id) }" >> "$FILE"
            else
                echo "    public func legacyOp${k}() { let x = $k * 2; print(x) }" >> "$FILE"
            fi
        done
        echo "}" >> "$FILE"
    done
    commit_changes "feat: Add noisy module $i with cross-type dependencies"
done
