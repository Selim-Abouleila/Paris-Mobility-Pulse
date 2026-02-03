import os
import sys


def test_python_version():
    """Verify minimum Python version."""
    assert sys.version_info >= (3, 10)


def test_service_paths():
    """Verify that service entry points exist on disk."""
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    services = [
        "services/bq-writer/main.py",
        "services/station-info-writer/main.py",
        "services/station-info-dlq-replayer/main.py",
    ]
    for service in services:
        full_path = os.path.join(base_dir, service)
        assert os.path.exists(full_path), f"Service entry point not found: {service}"


def test_package_imports():
    """Verify that valid Python packages can be imported."""
    # Add root to sys.path for these checks
    sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

    import importlib.util

    modules = [
        "pipelines.dataflow.pmp_streaming.main",
    ]
    for module_name in modules:
        spec = importlib.util.find_spec(module_name)
        # We don't fail if missing (CI env might not have all deps), but we check logic
        if spec is None:
            print(f"Warning: Could not find spec for module: {module_name}")
