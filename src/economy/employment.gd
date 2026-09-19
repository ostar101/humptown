class_name Employment
extends RefCounted
## The player's job, and how they are doing at it (D-042).
##
## One job at a time, from `data/jobs.json`: given by the background at the
## start, or asked for in conversation with whoever hires for it. Casual
## work — the worksite takes anyone for the day — needs no job at all.
## `standing` is how the employer sees the player's reliability, from 0 to 1:
## a full shift raises it, lateness and missed days lower it, and at zero the
## player is let go. Saved as the `work` section.

var job_id: String = ""
var standing: float = 1.0
var shifts_worked: int = 0
var shifts_missed: int = 0
## Day index of the last shift worked (any job, casual included), -1 never.
var last_worked_day: int = -1
## Day index the current job began; shifts before it cannot be missed.
var hired_day: int = -1
## Day index up to which missed shifts have been counted.
var checked_through_day: int = -1

const FULL_SHIFT_STANDING := 0.05
const LATE_STANDING := -0.05
const MISSED_STANDING := -0.25


func has_job() -> bool:
	return not job_id.is_empty()


func hire(p_job_id: String, day: int) -> void:
	job_id = p_job_id
	standing = 1.0
	shifts_worked = 0
	shifts_missed = 0
	hired_day = day
	checked_through_day = day


func leave() -> void:
	job_id = ""
	hired_day = -1


func record_shift(day: int, full: bool, late: bool, casual: bool) -> void:
	last_worked_day = day
	if casual:
		return
	shifts_worked += 1
	if late:
		standing = clampf(standing + LATE_STANDING, 0.0, 1.0)
	elif full:
		standing = clampf(standing + FULL_SHIFT_STANDING, 0.0, 1.0)


func record_missed() -> void:
	shifts_missed += 1
	standing = clampf(standing + MISSED_STANDING, 0.0, 1.0)


func to_dict() -> Dictionary:
	return {
		"job": job_id, "standing": standing, "worked": shifts_worked, "missed": shifts_missed,
		"last_worked_day": last_worked_day, "hired_day": hired_day, "checked_through_day": checked_through_day,
	}


func from_dict(d: Dictionary) -> void:
	job_id = str(d.get("job", ""))
	standing = clampf(float(d.get("standing", 1.0)), 0.0, 1.0)
	shifts_worked = int(d.get("worked", 0))
	shifts_missed = int(d.get("missed", 0))
	last_worked_day = int(d.get("last_worked_day", -1))
	hired_day = int(d.get("hired_day", -1))
	checked_through_day = int(d.get("checked_through_day", hired_day))
