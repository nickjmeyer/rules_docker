# Copyright 2017 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""A rule for creating a Python container image.

The signature of this rule is compatible with py_binary.
"""

load(
    "//container:container.bzl",
    "container_pull",
)
load(
    "//lang:image.bzl",
    "app_layer",
)
load(
    "//repositories:go_repositories.bzl",
    _go_deps = "go_deps",
)
load(
    "//toolchains:py_toolchains.bzl",
    _py_toolchains = "py_toolchains",
)

# Load the resolved digests.
load(":python3.bzl", "DIGESTS")

def repositories():
    """Import the dependencies of the py3_image rule.

    Call the core "go_deps" function to reduce boilerplate. This is
    idempotent if folks call it themselves.
    """
    _go_deps()

    # Register the default py_toolchain / platform for containerized execution
    if "container_py_toolchain" not in native.existing_rules().keys():
        _py_toolchains(name = "container_py_toolchain")
    native.register_toolchains(
        "@io_bazel_rules_docker//toolchains:container_py_toolchain",
        "@container_py_toolchain//:container_cc_toolchain",
    )
    native.register_execution_platforms("@io_bazel_rules_docker//platforms:local_container_platform")

    excludes = native.existing_rules().keys()
    if "py3_image_base" not in excludes:
        container_pull(
            name = "py3_image_base",
            registry = "gcr.io",
            repository = "distroless/python3",
            digest = DIGESTS["latest"],
        )
    if "py3_debug_image_base" not in excludes:
        container_pull(
            name = "py3_debug_image_base",
            registry = "gcr.io",
            repository = "distroless/python3",
            digest = DIGESTS["debug"],
        )

DEFAULT_BASE = select({
    "@io_bazel_rules_docker//:debug": "@py3_debug_image_base//image",
    "@io_bazel_rules_docker//:fastbuild": "@py3_image_base//image",
    "@io_bazel_rules_docker//:optimized": "@py3_image_base//image",
    "//conditions:default": "@py3_image_base//image",
})

def py3_image(name, base = None, deps = [], layers = [], **kwargs):
    """Constructs a container image wrapping a py_binary target.

  Args:
    name: Name of the py3_image rule target.
    base: Base image to use for the py3_image.
    deps: Dependencies of the py3_image.
    layers: Augments "deps" with dependencies that should be put into
           their own layers.
    **kwargs: See py_binary.
  """
    binary_name = name + ".binary"

    if "main" not in kwargs:
        kwargs["main"] = name + ".py"

    # TODO(mattmoor): Consider using par_binary instead, so that
    # a single target can be used for all three.

    native.py_binary(
        name = binary_name,
        python_version = "PY3",
        deps = deps + layers,
        exec_compatible_with = ["@io_bazel_rules_docker//platforms:run_in_container"],
        **kwargs
    )

    # TODO(mattmoor): Consider making the directory into which the app
    # is placed configurable.
    base = base or DEFAULT_BASE
    for index, dep in enumerate(layers):
        base = app_layer(name = "%s.%d" % (name, index), base = base, dep = dep)
        base = app_layer(name = "%s.%d-symlinks" % (name, index), base = base, dep = dep, binary = binary_name)

    visibility = kwargs.get("visibility", None)
    tags = kwargs.get("tags", None)
    app_layer(
        name = name,
        base = base,
        entrypoint = ["/usr/bin/python"],
        binary = binary_name,
        visibility = visibility,
        tags = tags,
        args = kwargs.get("args"),
        data = kwargs.get("data"),
        testonly = kwargs.get("testonly"),
    )
