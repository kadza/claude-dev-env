# Screenshots are deleted after Claude reads them

After Claude reads a screenshot, it `rm`s the file. This keeps the folder tiny and keeps "newest file" unambiguous over a long session. Rejected: moving it to a `seen/` subfolder (reversible, but the simpler tiny-folder outcome was preferred); leaving it in place (the folder would grow and "newest" would get muddier, making the read-write mount pointless).
