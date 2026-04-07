import cua_bench as cb


@cb.tasks_config(split="train")
def load():
    return [
        cb.Task(
            description="Open Reminders and create a new reminder called 'Buy groceries' in the default list.",
            metadata={"reminder_name": "Buy groceries"},
            computer={
                "provider": "native",
                "setup_config": {"os_type": "macos", "width": 1440, "height": 900},
            },
        )
    ]


@cb.setup_task(split="train")
async def start(task_cfg: cb.Task, session: cb.DesktopSession):
    """Launch Reminders app."""
    await session.apps.reminders.launch()


@cb.evaluate_task(split="train")
async def evaluate(task_cfg: cb.Task, session: cb.DesktopSession) -> list[float]:
    """Check if the reminder was created using osascript getter."""
    target_name = task_cfg.metadata["reminder_name"]

    # App helper uses osascript internally to query Reminders
    reminders = await session.apps.reminders.get_incomplete_reminders()

    for reminder in reminders:
        if reminder["name"] == target_name:
            return [1.0]
    return [0.0]


if __name__ == "__main__":
# These methods run osascript commands under the hood
    #notes = await session.apps.notes.get_all_notes()
    #events = await session.apps.calendar.get_events_today()
    #reminders = await session.apps.reminders.get_incomplete_reminders()
    cb.interact(__file__)
