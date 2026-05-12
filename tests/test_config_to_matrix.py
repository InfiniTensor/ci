import pytest
import yaml

import config_to_matrix
from utils import normalize_config


def _multi_platform_config():
    return normalize_config(
        {
            "platforms": {
                "nvidia": {
                    "image": {"dockerfile": ".ci/images/nvidia/"},
                    "jobs": {
                        "gpu": {
                            "type": "unittest",
                            "resources": {"timeout": 3600},
                            "stages": [{"name": "test", "run": "pytest nvidia"}],
                        }
                    },
                },
                "ascend": {
                    "image": {"dockerfile": ".ci/images/ascend/"},
                    "jobs": {
                        "npu": {
                            "type": "unittest",
                            "resources": {"timeout": 3600},
                            "stages": [{"name": "test", "run": "pytest ascend"}],
                        }
                    },
                },
                "metax": {
                    "image": {"dockerfile": ".ci/images/metax/"},
                    "jobs": {
                        "gpu": {
                            "type": "unittest",
                            "resources": {"timeout": 1800},
                            "stages": [{"name": "test", "run": "pytest metax"}],
                        }
                    },
                },
            }
        }
    )


def _matrix_ids(matrix):
    return [entry["id"] for entry in matrix["include"]]


def test_convert_by_job_type_filters_to_requested_platform():
    matrices = config_to_matrix.convert_by_job_type(
        _multi_platform_config(), platform_filter="nvidia"
    )

    assert list(matrices) == ["unittest"]
    assert _matrix_ids(matrices["unittest"]) == ["nvidia_gpu"]


def test_convert_by_job_type_all_keeps_all_platforms():
    matrices = config_to_matrix.convert_by_job_type(
        _multi_platform_config(), platform_filter="all"
    )

    assert _matrix_ids(matrices["unittest"]) == [
        "nvidia_gpu",
        "ascend_npu",
        "metax_gpu",
    ]


def test_convert_by_job_type_accepts_platform_list():
    matrices = config_to_matrix.convert_by_job_type(
        _multi_platform_config(), platform_filter="nvidia,metax"
    )

    assert _matrix_ids(matrices["unittest"]) == [
        "nvidia_gpu",
        "metax_gpu",
    ]


def test_convert_by_job_type_rejects_unknown_platform():
    with pytest.raises(ValueError, match="No jobs found for platform 'unknown'"):
        config_to_matrix.convert_by_job_type(
            _multi_platform_config(), platform_filter="unknown"
        )


def test_main_prints_clean_error_for_unknown_platform(tmp_path, monkeypatch, capsys):
    config_path = tmp_path / "ci_config.yml"
    config_path.write_text(
        yaml.safe_dump(
            {
                "platforms": {
                    "nvidia": {
                        "image": {"dockerfile": ".ci/images/nvidia/"},
                        "jobs": {
                            "gpu": {
                                "resources": {"timeout": 3600},
                                "stages": [{"name": "test", "run": "pytest"}],
                            }
                        },
                    }
                }
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setattr(
        "sys.argv",
        [
            "config_to_matrix.py",
            "--config",
            str(config_path),
            "--dump-by-type",
            "--platform",
            "unknown",
        ],
    )

    assert config_to_matrix.main() == 1

    captured = capsys.readouterr()
    assert captured.err == "error: No jobs found for platform 'unknown'\n"
