"""IN-meetings pipeline: a per-meeting job worker spawned by the Swift app (ADR-009).

Phases (resumable): queued → transcribing → diarizing → packaging → done | failed.
The job + status + outputs are co-located in the meeting's recording folder.
"""

__version__ = "0.1.0"
