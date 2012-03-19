
Introduction
============

Patchwatch is modeled after the
[Patchwork](http://ozlabs.org/~jk/projects/patchwork/) tool, but designed for
[Darcs](http://www.darcs.org). It was created for use on the Darcs mailing list
but was never put to use.

I believe most of it was implemented but since it never saw real use I'm sure
there are plenty of issues.

Usage
=====

The code is split into three parts:

Webserver
---------

`patchwatch.rb` is a web server that allows users to view the patches and
associated discussions. Administrators can change the state of the patches here
as well.

Email Parser
------------

Incoming emails from the mailing list should all be passed through
`patchwatch_parse.rb`. This script looks for patches and replies to patches and
enters them into the database.

Administration CLI
------------------

While the web interface can be used for administrators to change the state of
patches it is often much more useful to be able to do this from the mail
client. The `patchwatch_ctrl.sh` shows an example of how the state of a patch
can be changed from the command line.

