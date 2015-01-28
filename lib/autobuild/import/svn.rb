require 'autobuild/subcommand'
require 'autobuild/importer'

module Autobuild
    class SVN < Importer
	# Creates an importer which gets the source for the Subversion URL +source+.
	# The following options are allowed:
	# [:svnup] options to give to 'svn up'
	# [:svnco] options to give to 'svn co'
	#
	# This importer uses the 'svn' tool to perform the import. It defaults
	# to 'svn' and can be configured by doing 
	#   Autobuild.programs['svn'] = 'my_svn_tool'
        def initialize(source, options = {})
            source = [*source].join("/")
            svnopts, common = Kernel.filter_options options,
                :svnup => [], :svnco => [], :revision => nil,
                :repository_id => "svn:#{source}"
            common[:repository_id] = svnopts.delete(:repository_id)
            relocate(source, svnopts)
            super(common.merge(repository_id: svnopts[:repository_id]))
        end

        def relocate(root, options = Hash.new)
            @source = [*root].join("/")
            @options_up = [*options[:svnup]]
            @options_co = [*options[:svnco]]
            if rev = options[:revision]
                @options_up << "--revision" << rev
                @options_co << "--revision" << rev
            end
        end

        private

        def run_svn(package, *args, &block)
            options = Hash.new
            if args.last.kind_of?(Hash)
                options = args.pop
            end
            options, other_options = Kernel.filter_options options,
                working_directory: package.importdir, retry: true
            options = options.merge(other_options)
            package.run(:import, Autobuild.tool(:svn), *args, options, &block)
        end

        # Returns the result of the 'svn info' command
        #
        # It automatically runs svn upgrade if needed
        #
        # @param [Package] package
        # @return [Array<String>] the lines returned by svn info, with the
        #   trailing newline removed
        # @raises [SubcommandFailed] if svn info failed
        # @raises [ConfigException] if the working copy is not a subversion
        #   working copy
        def svn_info(package)
            old_lang, ENV['LC_ALL'] = ENV['LC_ALL'], 'C'
            begin
                svninfo = run_svn(package, 'info')
            rescue SubcommandFailed => e
                if e.output.find { |l| l =~ /svn upgrade/ }
                    # Try svn upgrade and info again
                    run_svn(package, 'upgrade', retry: false)
                    svninfo = run_svn(package, 'info')
                else raise
                end
            end

            if !svninfo.grep(/is not a working copy/).empty?
                raise ConfigException.new(package, 'import'),
                    "#{package.importdir} does not appear to be a Subversion working copy"
            end
            svninfo
        ensure
            ENV['LC_ALL'] = old_lang
        end

        # Returns the SVN revision of the package
        #
        # @param [Package] package
        # @return [Integer]
        # @raises ConfigException if 'svn info' did not return a Revision field
        # @raises (see svn_info)
        def svn_revision(package)
            svninfo = svn_info(package)
            revision = svninfo.grep(/^Revision: /).first
            if !revision
                raise ConfigException.new(package, 'import'), "cannot get SVN information for #{package.importdir}"
            end
            revision =~ /Revision: (\d+)/
            Integer($1)
        end

        # Returns the URL of the remote SVN repository
        #
        # @param [Package] package
        # @return [String]
        # @raises ConfigException if 'svn info' did not return a URL field
        # @raises (see svn_info)
        def svn_url(package)
            svninfo = svn_info(package)
            url = svninfo.grep(/^URL: /).first
            if !url
                raise ConfigException.new(package, 'import'), "cannot get SVN information for #{package.importdir}"
            end
            url.chomp =~ /URL: (.+)/
            $1
        end

        def update(package,only_local=false) # :nodoc:
            if only_local
                package.warn "%s: the svn importer does not support local updates, skipping"
                return
            end

            url = svn_url(package)
            if url != @source
                raise ConfigException.new(package, 'import'), "current checkout found at #{package.importdir} is from #{url}, was expecting #{@source}"
            end
            run_svn(package, 'up', "--non-interactive", *@options_up)
        end

        def checkout(package) # :nodoc:
            run_svn(package, 'co', "--non-interactive", *@options_co, @source, package.importdir, working_directory: nil)
        end
    end

    # Creates a subversion importer which import the source for the Subversion
    # URL +source+. The allowed values in +options+ are described in SVN.new.
    def self.svn(source, options = {})
        SVN.new(source, options)
    end
end

