require 'autobuild/packages/autotools'
require 'open3'

module Autobuild
    class GenomModule < Autotools
        def prepare
            super
            get_requires
            get_provides
        end
        def genomstamp; "#{srcdir}/.genom/genom-stamp" end

        def cpp_options
            @options[:genomflags].to_a.find_all { |opt| opt =~ /^-D/ }
        end

        def get_requires
            cpp = ($PROGRAMS['cpp'] || 'cpp')
            Open3.popen3("#{cpp} #{cpp_options.join(" ")} #{srcdir}/#{target}.gen") do |cin, out, err|
                out.each_line { |line|
                    if line =~ /^\s*requires\s*:\s*([\w\-]+(?:\s*,\s*[\w\-]+)*);/
                        $1.split(/, /).each { |name| 
                            depends_on name
                        }
                    elsif line =~ /^\s*requires/
                        puts "failed to match #{line}"
                    end
                }
            end
        end

        def depends_on(name)
            super
            file genomstamp => Package.name2target(name)
        end

        def get_provides
            File.open("#{srcdir}/configure.ac.user") do |f|
                f.each_line { |line|
                    if line =~ /^\s*EXTRA_PKGCONFIG\s*=\s*"?([\w\-]+(?:\s+[\w\-]+)*)"?/
                        $1.split(/\s+/).each { |pkg|
                            provides pkg
                        }
                    end
                }
            end
        end
            

        def regen_targets
            cmdline = [ 'genom', target ] | @options[:genomflags].to_a

            file buildstamp => genomstamp
            file genomstamp => [ :genom, "#{srcdir}/#{target}.gen" ] do
                Dir.chdir(srcdir) {
                    Subprocess.run(target, 'genom', *cmdline)
                }
            end

            acuser = "#{srcdir}/configure.ac.user"
            if File.exists?(acuser)
                file "#{srcdir}/configure" => acuser do
                    # configure does not depend on the .gen file
                    # since the generation takes care of rebuilding configure
                    # if .gen has changed
                    Subprocess.run(target, 'genom', File.expand_path('autogen'))
                end
            end
        end

        factory :genom, self
    end
end

