#!/usr/bin/env python3
"""Validate release gates with synthetic archives, never release binaries."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
PAIRS = [
    ("redis-server.exe", "redis-server.exe"),
    ("redis-server.exe", "redis-sentinel.exe"),
    ("redis-check-aof.exe", "redis-check-aof.exe"),
    ("redis-check-rdb.exe", "redis-check-rdb.exe"),
    ("redis-cli.exe", "redis-cli.exe"),
    ("redis-benchmark.exe", "redis-benchmark.exe"),
    ("EventLog.dll", "EventLog.dll"),
]


def digest(data, algorithm="sha256"):
    return hashlib.new(algorithm, data).hexdigest()


class ReleaseAssets(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="redis-release-fixture-")
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.fixture()

    def write_json(self, name, value):
        (self.path / name).write_text(json.dumps(value))

    def mutate(self, name, change):
        data = json.loads((self.path / name).read_text())
        change(data)
        self.write_json(name, data)

    def fixture(self, version="8.10.2", revision=1, checksum_marker=" "):
        for path in self.path.iterdir():
            path.unlink()
        tls = version.startswith("8.")
        tag = f"v{version}-windows.{revision}"
        self.env = dict(os.environ, RELEASE_TAG=tag,
                        RELEASE_SOURCE_SHA="a" * 40, RELEASE_SOURCE_TREE="b" * 40,
                        RELEASE_SOURCE_BRANCH=f"mingw-{version.rsplit('.', 1)[0]}",
                        RELEASE_VERSION=version, RELEASE_REVISION=str(revision),
                        RELEASE_QUALIFICATION_RUN_ID="42", GITHUB_REPOSITORY="example/redis")
        buildinfo = (f"Redis version: {version}\nWindows package revision: {revision}\n"
                     f"Release tag: {tag}\nSource commit: {'a' * 40}\nSource tree: {'b' * 40}\n"
                     + ("TLS build: yes (built in; static OpenSSL)\nOpenSSL version: 3.6.3\n"
                        "OpenSSL package: mingw-w64-x86_64-openssl 3.6.3-1\n" if tls else "TLS build: no\n"))
        files = {name: ("synthetic " + name + "\n").encode() for _, name in PAIRS}
        for alias in ("redis-sentinel.exe", "redis-check-aof.exe", "redis-check-rdb.exe"):
            files[alias] = files["redis-server.exe"]
        files["BUILDINFO.txt"] = buildinfo.encode()
        files["PACKAGE-MANIFEST.txt"] = ("\n".join(sorted(files)) + "\n").encode()
        archive_name = f"Redis-x64-{version}-mingw-r{revision}.zip"
        with zipfile.ZipFile(self.path / archive_name, "w") as archive:
            for name, data in files.items():
                archive.writestr(name, data)
        archive_sha = digest((self.path / archive_name).read_bytes())
        (self.path / "SHA256SUMS.txt").write_text(f"{archive_sha} {checksum_marker}{archive_name}\n")
        (self.path / "BUILDINFO.txt").write_text(buildinfo)
        (self.path / "package-manifest.txt").write_bytes(files["PACKAGE-MANIFEST.txt"])
        identity = "build_file\tpackage_file\tsha256\tsize\n" + "".join(
            f"{source}\t{name}\t{digest(files[name])}\t{len(files[name])}\n" for source, name in PAIRS)
        (self.path / "package-binary-identity.tsv").write_text(identity)
        for name in ("TEST-REPORT.md", "benchmark.csv", "toolchain.txt"):
            (self.path / name).write_text("synthetic test fixture\n")
        package_tls = {"build": "no"}
        if tls:
            package_tls = {"build": "yes", "linkage": "static", "openssl_version": "3.6.3",
                           "openssl_package": "mingw-w64-x86_64-openssl 3.6.3-1"}
        self.write_json("release-evidence.json", {
            "release": {"tag": tag, "branch": self.env["RELEASE_SOURCE_BRANCH"],
                        "version": version, "windows_revision": revision},
            "source": {"commit": "a" * 40, "tree": "b" * 40},
            "package": {"archive": archive_name, "sha256": archive_sha,
                        "scope": "Redis core only", "tls": package_tls},
            "qualification": {"all_required_tests": "passed", "release_binary_identity": "passed",
                              "transports": ["plaintext", "TLS"] if tls else ["plaintext"],
                              "workflow_url": "https://github.com/example/redis/actions/runs/42"},
            "attestations": {"required_before_publication": {"build_provenance": True, "sbom": True}}})
        package = {"SPDXID": "SPDXRef-Package", "packageFileName": archive_name,
                   "filesAnalyzed": True, "checksums": [{"algorithm": "SHA256", "checksumValue": archive_sha}],
                   "packageVerificationCode": {"packageVerificationCodeValue": digest(
                       "".join(sorted(digest(data, "sha1") for data in files.values())).encode(), "sha1")}}
        sbom = {"spdxVersion": "SPDX-2.3", "SPDXID": "SPDXRef-DOCUMENT", "packages": [package],
                "files": [], "relationships": []}
        for index, (name, data) in enumerate(files.items()):
            file_id = f"SPDXRef-File-{index}"
            sbom["files"].append({"SPDXID": file_id, "fileName": "./" + name,
                                  "checksums": [{"algorithm": alg.upper(), "checksumValue": digest(data, alg)}
                                                for alg in ("sha1", "sha256")]})
            sbom["relationships"].append({"spdxElementId": "SPDXRef-Package", "relationshipType": "CONTAINS",
                                           "relatedSpdxElement": file_id})
        if tls:
            sbom["packages"].append({"SPDXID": "SPDXRef-OpenSSL", "name": "OpenSSL", "filesAnalyzed": False,
                                      "licenseDeclared": "Apache-2.0", "versionInfo": "3.6.3",
                                      "sourceInfo": "MSYS2 package: mingw-w64-x86_64-openssl 3.6.3-1"})
            sbom["relationships"].append({"spdxElementId": "SPDXRef-Package", "relationshipType": "STATIC_LINK",
                                           "relatedSpdxElement": "SPDXRef-OpenSSL"})
        self.write_json("sbom.spdx.json", sbom)

    def verify(self, passed=False):
        result = subprocess.run(["bash", str(ROOT / "scripts/verify-release-assets.sh"), str(self.path)],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, passed, result.stdout + result.stderr)

    def test_release_matrix(self):
        for version, revision in (("8.10.2", 1), ("8.8.3", 1), ("7.2.16", 2), ("6.2.24", 2)):
            for marker in (" ", "*"):
                with self.subTest(version=version, checksum_marker=marker):
                    self.fixture(version, revision, checksum_marker=marker)
                    self.verify(True)

    def test_checksum_record_corruption(self):
        for marker in (" ", "*"):
            for corruption in ("digest", "name", "extra_record", "marker"):
                with self.subTest(checksum_marker=marker, corruption=corruption):
                    self.fixture(checksum_marker=marker)
                    path = self.path / "SHA256SUMS.txt"
                    record = path.read_text()
                    if corruption == "digest":
                        record = "0" * 64 + record[64:]
                    elif corruption == "name":
                        record = record.replace("Redis-x64-", "Other-x64-")
                    elif corruption == "extra_record":
                        record += record
                    else:
                        record = record[:65] + "?" + record[66:]
                    path.write_text(record)
                    self.verify()

    def test_revision_one_bytes_cannot_publish_as_revision_two(self):
        self.fixture("7.2.16", 1)
        self.env.update(RELEASE_REVISION="2", RELEASE_TAG="v7.2.16-windows.2")
        self.verify()

    def test_invalid_release_inputs(self):
        for key, value in (("RELEASE_SOURCE_SHA", "c" * 40), ("RELEASE_SOURCE_TREE", "c" * 40),
                           ("RELEASE_TAG", "v8.10.2-windows.2"), ("RELEASE_QUALIFICATION_RUN_ID", "43"),
                           ("RELEASE_SOURCE_BRANCH", "mingw-7.4")):
            with self.subTest(key=key):
                self.fixture()
                self.env[key] = value
                self.verify()

    def test_wrong_transport_or_scope(self):
        for change in (lambda d: d["qualification"].update(transports=["plaintext"]),
                       lambda d: d["qualification"].pop("transports"),
                       lambda d: d["package"]["tls"].update(build="no"),
                       lambda d: d["package"].update(scope="bundled modules")):
            self.fixture()
            self.mutate("release-evidence.json", change)
            self.verify()

    def test_openssl_provenance(self):
        self.mutate("release-evidence.json", lambda d: d["package"]["tls"].update(openssl_version="3.0.0"))
        self.verify()

    def test_revision_evidence_mismatch(self):
        self.mutate("release-evidence.json", lambda d: d["release"].update(windows_revision=2))
        self.verify()

    def test_missing_or_extra_asset(self):
        (self.path / "benchmark.csv").unlink()
        self.verify()
        self.fixture()
        (self.path / "extra.txt").write_text("unexpected")
        self.verify()

    def test_buildinfo_differs_from_archive(self):
        with (self.path / "BUILDINFO.txt").open("a") as output:
            output.write("changed\n")
        self.verify()

    def test_spdx_corruption(self):
        for change in (lambda d: d["files"].append(d["files"][0]),
                       lambda d: d["files"][0]["checksums"][0].update(checksumValue="0" * 40),
                       lambda d: d["packages"][0]["packageVerificationCode"].update(packageVerificationCodeValue="0" * 40)):
            self.fixture()
            self.mutate("sbom.spdx.json", change)
            self.verify()

    def test_binary_identity_corruption(self):
        path = self.path / "package-binary-identity.tsv"
        lines = path.read_text().splitlines()
        columns = lines[1].split("\t")
        columns[2] = "0" * 64
        lines[1] = "\t".join(columns)
        path.write_text("\n".join(lines) + "\n")
        self.verify()


if __name__ == "__main__":
    unittest.main()
