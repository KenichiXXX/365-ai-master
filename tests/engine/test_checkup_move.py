import subprocess, sys

def test_checkup_importable_without_cloud():
    code = (
        "import sys\n"
        "import agentfit.checkup as c\n"
        "assert 'cloud' not in sys.modules, sorted(m for m in sys.modules if m.startswith('cloud'))\n"
        "dims, _ = c.compute_checkup({}, {}, {}, None, 0.0)\n"
        "print(c.overall_from_dimensions(dims))\n"
    )
    out = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True)
    assert out.returncode == 0, out.stderr
    assert out.stdout.strip() == "91"

def test_cloud_reexports_same_objects():
    import agentfit.checkup as a, cloud.coach as c, agentfit.models.checkup as am, cloud.models as cm
    assert c.compute_checkup is a.compute_checkup
    assert c.overall_from_dimensions is a.overall_from_dimensions
    assert cm.DimensionScore is am.DimensionScore
