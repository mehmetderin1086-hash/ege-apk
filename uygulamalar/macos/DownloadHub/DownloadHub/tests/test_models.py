from downloadhub.schemas import JobStatus


def test_job_status_contract_is_complete() -> None:
    assert {status.value for status in JobStatus} == {
        "inspecting",
        "queued",
        "scheduled",
        "downloading",
        "postprocessing",
        "paused",
        "retry_wait",
        "completed",
        "failed",
        "cancelled",
        "interrupted",
    }
