# `clone` is a separate command, not an overload of `seed`

Seeding from an existing GitHub repo is a separate command (`clone`), not an overload of `seed`'s second argument or a flag. The two flows differ fundamentally (git clone of a real remote vs. `git init` scaffold), so a distinct verb keeps each script simple and its behavior obvious. Rejected: overloading `seed <tech> <arg>` with URL-vs-name detection (a heuristic that can misfire, and mixes two behaviors in one script); an explicit `--clone` flag (more typing, still one overloaded command).
