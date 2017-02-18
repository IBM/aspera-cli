require "thor"

module Asperalm
  module Cli
    class Files < Thor
      desc "add <name> <url>", "Adds a remote named <name> for the repository at <url>"
      long_desc <<-LONGDESC
      Adds a remote named <name> for the repository at <url>. The command git fetch <name> can then be used to create and update
      remote-tracking branches <name>/<branch>.
 
      With -f option, git fetch <name> is run immediately after the remote information is set up.
 
      With --tags option, git fetch <name> imports every tag from the remote repository.
 
      With --no-tags option, git fetch <name> does not import tags from the remote repository.
 
      With -t <branch> option, instead of the default glob refspec for the remote to track all branches under $GIT_DIR/remotes/<name>/, a
      refspec to track only <branch> is created. You can give more than one -t <branch> to track multiple branches without grabbing all
      branches.
 
      With -m <master> option, $GIT_DIR/remotes/<name>/HEAD is set up to point at remote's <master> branch. See also the set-head
      command.
 
      When a fetch mirror is created with --mirror=fetch, the refs will not be stored in the refs/remotes/ namespace, but rather
      everything in refs/ on the remote will be directly mirrored into refs/ in the local repository. This option only makes sense in
      bare repositories, because a fetch would overwrite any local commits.
 
      When a push mirror is created with --mirror=push, then git push will always behave as if --mirror was passed.
      LONGDESC
      option :t, :banner => "<branch>"
      option :m, :banner => "<master>"
      options :f => :boolean, :tags => :boolean, :mirror => :string
      def add(name, url)
        # implement git remote add
      end

      desc "rename <old> <new>", "Rename the remote named <old> to <new>"
      def rename(old, new)
      end
    end

    class ThorMain < Thor
      desc "fetch <repository> [<refspec>...]", "Download objects and refs from another repository"
      options :all => :boolean, :multiple => :boolean
      option :append, :type => :boolean, :aliases => :a
      def fetch(respository, *refspec)
        # implement git fetch here
      end

      desc "remote SUBCOMMAND ...ARGS", "manage set of tracked repositories"
      subcommand "files", Files
    end
  end
end

Asperalm::Cli::ThorMain.start(ARGV)
