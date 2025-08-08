# SPDY-License-Identifier: GPL-2.0-or-later
# makeatom2.rb
#
# Atom Syndication Format(RFC4287)のfeedを出力するプラグインです。
# makerss.rbをベースに作成させていただきました。
# できるだけmakerss.rbの設定と共通にしています。
#
# options configurable through settings:
#   @conf['makerss.hidecontent'] : hide full-text content. default: false
#   @conf['makerss.shortdesc'] : shorter description. default: false
#   @conf['makerss.comment_link'] : insert tsukkomi's link. default: false
#
# options to be edited in tdiary.conf:
#   @conf['makeatom.file']  : local file name of RSS file. default: 'index.atom.xml'.
#   @conf['makeatom.url']   : URL of RSS file.
#   @conf['makeatom.no_comments.file']  : local file name of RSS file without
#                            comments. default: 'no_comments.atom.xml'.
#   @conf['makeatom.no_comments.url']   : URL of RSS file without TSUKOMI.
#   @conf.description      : desciption of the diary
#   @conf['makerss.partial'] : how much portion of body to be in description
#                            used when makerss.shortdesc, default: 0.25
#   @conf['makeatom.suffix'] : strings which are appended to the title tag.
#   @conf['makeatom.no_comments.suffix'] : strings which are appended to
#                            the title tag of the commentless rdf.
#
#   CAUTION: Before using, make 'index.atom.xml' and 'no_comments.atom.xml' file
#            into the directory of your diary, and permit writable to httpd.
#
# Copyright (c) 2009 TADA Tadashi <t@tdtds.jp>
# Copyright (c) 2025 eniehack
# Distributed under the GPL2 or any later version.
#

if /^append|replace|comment|showcomment|startup$/ =~ @mode then
	unless @conf.description
		@conf.description = @conf['whatsnew_list.rdf.description']
	end
	module ::TDiary
		class AtomSection
			attr_reader :id, :time, :section

			def self.from_json(id, json)
				self.new(id, nil, nil, data: JSON.load(json))
			end

			# 'id' has 'YYYYMMDDpNN' format (p or c).
			# 'time' is Last-Modified this section as a Time object.
			def initialize( id, time = nil, section = nil, opts = {} )
				@id = id
				if opts[:data]
					@time = opts[:data]['time']
					@is_comment = opts[:data]['is_comment']
					@section = opts[:data]['section']
				else
					@time = time_string(time)
					@is_comment = section.respond_to?(:name)
					@section = section_to_hash(section)
				end
			end

			def body?
				!@is_comment
			end

			def <=>( other )
				other.time <=> @time
			end

			def to_json
				{
					'id' => @id,
					'time' => @time,
					'section' => @section,
					'is_comment' => @is_comment
				}.to_json
			end

		private
			def time_string(time)
				g = time.dup.gmtime
				l = Time::local( g.year, g.month, g.day, g.hour, g.min, g.sec )
				tz = (g.to_i - l.to_i)
				zone = sprintf( "%+03d:%02d", tz / 3600, tz % 3600 / 60 )
				time.strftime( "%Y-%m-%dT%H:%M:%S" ) + zone
			end

			def section_to_hash(section)
				sec ||= {}
				sec['body'] = section.respond_to?(:body_to_html) ? section.body_to_html : section.body
				sec['subtitle'] = section.subtitle_to_html if section.respond_to?(:subtitle_to_html)
				sec['visibility'] = section.visible? rescue true
				sec['category'] = section.categories rescue []

				sec['name'] = section.name if section.respond_to?(:name)
				return sec
			end
		end
	end
end

@makeatom_files = @makeatom_files || []

class MakeAtomFull
	include ERB::Util
	include TDiary::ViewHelper

	def initialize(conf, cgi = CGI.new)
		@conf, @cgi = conf, cgi
		@item_num = 0
	end

	def title
		@conf['makeatom.suffix'] || ''
	end

	def head( str )
		@head = str
		@head.sub!( /<\/title>/, "#{h title}</title>" )
	end

	def foot( str ); @foot = str; end
	def image( str ); @image = str; end
	def banner( str ); @banner = str; end

	def item( seq, body, rdfsec )
		@item_num += 1
		return if @item_num > 15
		@seq = '' unless @seq
		@seq << seq
		@body = '' unless @body
		@body << body
	end

	def xml
		xml = @head.to_s
		xml << @image.to_s
		xml << @banner.to_s
		xml << @body.to_s
		xml << @foot.to_s
		xml.gsub( /[\x00-\x1f]/ ){|s| s =~ /[\r\n\t]/ ? s : ""}
	end

	def file
    f = @conf['makeatom.file'] || 'index.atom.xml'
    f = 'index.atom.xml' if f.empty?
		f =~ %r|^/| ? f : "#{document_root}/#{f}"
	end

	def writable?
		if FileTest::writable?( file ) then
			return true
		elsif FileTest::exist?( file )
			return false
		else # try to create
			begin
				File::open( file, 'w' ){|f|}
				return true
			rescue
				return false
			end
		end
	end

	def write( encoder )
		begin
			File::open( file, 'w' ) do |f|
				f.write( encoder.call( xml ) )
			end
		rescue
		end
	end

	def url
		u = @conf['makeatom.url'] || "#{base_url}#{File.basename(file)}"
		u = "#{base_url}#{File.basename(file)}" if u.empty?
		u
	end

	def document_root
		if @cgi.is_a?(RackCGI)
			File.join(TDiary.server_root, 'public')
		else
			TDiary.server_root
		end
	end
end

@makeatom_files << MakeAtomFull::new(@conf, @cgi)

class MakeAtomNoComments < MakeAtomFull
	def title
		@conf['makeatom.no_comments.suffix'] || '(without comments)'
	end

	def item( seq, body, rdfsec )
		return unless rdfsec.body?
		super
	end

	def file
    f = @conf['makeatom.no_comments.file'] || 'no_comments.atom.xml'
    f = 'no_comments.atom.xml' if f.empty?
		f =~ %r|^/| ? f : "#{document_root}/#{f}"
	end

	def write( encoder )
		return unless @conf['makerss.no_comments']
		super( encoder )
	end

	def url
		return nil unless @conf['makerss.no_comments']
		u = @conf['makeatom.no_comments.url'] ||"#{base_url}#{File.basename(file)}"
		u = "#{base_url}#{File.basename(file)}" if u.empty?
		u
	end
end

@makeatom_files << MakeAtomNoComments::new(@conf, @cgi)

def makeatom_update
	def get(db, id)
		json = db.get(id)
		return nil unless json
		AtomSection.from_json(id, json) rescue nil
	end

	def set(db, id, section)
		db.set(id, section.to_json)
	end

	date = @date.strftime( "%Y%m%d" )
	diary = @diaries[date]

	uri = @conf.index.dup
	uri[0, 0] = base_url if %r|^https?://|i !~ @conf.index
	uri.gsub!( %r|/\./|, '/' )

	rsses = @makeatom_files

	transaction('makeatom') do |db|
		begin
			if /^append|replace$/ =~ @mode then
				format = "#{date}p%02d"
				index = 0
				diary.each_section do |section|
					index += 1
					id = format % index
					if diary.visible? and !get(db, id) then
						set(db, id, AtomSection::new( id, Time::now, section ))
					elsif !diary.visible? and get(db, id)
						db.delete(id)
					elsif diary.visible? and get(db, id)
						if get(db, id).section['body'] != section.body_to_html or
								get(db, id).section['subtitle'] != section.subtitle_to_html then
							set(db, id, AtomSection::new( id, Time::now, section ))
						end
					end
				end

				loop do
					index += 1
					id = format % index
					if get(db, id) then
						db.delete(id)
					else
						break
					end
				end
				set(db, 'p_updated', Time::now.iso8601)
			elsif /^comment$/ =~ @mode and @conf.show_comment
				id = "#{date}c%02d" % diary.count_comments( true )
				set(db, id, AtomSection::new( id, @comment.date, @comment ))
				set(db, 'c_updated', Time::now.iso8601)
			elsif /^showcomment$/ =~ @mode
				index = 0
				diary.each_comment do |comment|
					index += 1
					id = "#{date}c%02d" % index
					if !get(db, id) and (@conf.show_comment and comment.visible? and /^(TrackBack|Pingback)$/i !~ comment.name) then
						set(db, id, AtomSection::new( id, comment.date, comment ))
					elsif get(db, id) and !(@conf.show_comment and comment.visible? and /^(TrackBack|Pingback)$/i !~ comment.name)
						db.delete(id)
					end
				end
			end

			rsses.each{|rss| 
				if rss.class == MakeAtomFull then
					c_updated = db.get('c_updated')
					p_updated = db.get('p_updated')
					if not c_updated.nil? and not p_updated.nil? then
						updated = [Time.parse(c_updated), Time.parse(p_updated)].max
					else
						updated = Time::now
					end
					rss.head( makeatom_header( uri, updated ) )
				elsif rss.class == MakeAtomNoComments
					p_updated = db.get('p_updated')
					unless p_updated.nil? then
						updated = p_updated
					else
						updated = Time::now
					end
					rss.head( makeatom_header( uri, updated ) )
				end
			}
			db.keys.filter{|k| k.match?("updated") == false}.map{|k|get(db, k)}.sort.each_with_index do |rdfsec, idx|
				if rdfsec && rdfsec.section['visibility']
					rsses.each {|rss|
						rss.item( makerss_seq( uri, rdfsec ), makeatom_body( uri, rdfsec ), rdfsec )
					}
				end
				if idx > 50
					db.delete(rdfsec.id)
				end
			end
		end
	end

	if @conf.banner and not @conf.banner.empty?
		if /^http/ =~ @conf.banner
			rdf_image = @conf.banner
		else
			rdf_image = base_url + @conf.banner
		end
		rsses.each {|r| r.image( %Q[<image rdf:resource="#{h rdf_image}" />\n] ) }
	end

	rsses.each {|r|
		r.banner( makerss_banner( uri, rdf_image ) ) if rdf_image
		r.foot( makeatom_footer )
		r.write( Proc::new{|s| replace_entities( to_utf8( s ) )} )
	}
end

def makeatom_header( uri, updated )
  rdf_url = @conf['makeatom.url'] || "#{base_url}index.atom.xml"
  rdf_url = "#{base_url}index.atom.xml" if rdf_url.empty?

	desc = @conf.description || ''

	copyright = Time::now.strftime( "Copyright %Y #{@conf.author_name}" )
	copyright += " <#{@conf.author_mail}>" if @conf.author_mail and not @conf.author_mail.empty?
	copyright += ", copyright of comments by respective authors"

	formattedUpdated = updated
	if updated.class == String then
		formattedUpdated = Time.parse updated
	end

	header = %Q[<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xml:lang="#{h @conf.html_lang}">
	<id>#{h rdf_url}</id>
	<title>#{h @conf.html_title}</title>
	<link href="#{h uri}" rel="alternate" type="text/html" />
	<link href="#{h rdf_url}" rel="self" type="application/atom+xml" />
	<updated>#{h formattedUpdated.iso8601}</updated>
	<author>
    <name>#{h @conf.author_name}</name>
  </author>
	<rights>#{h copyright}</rights>
  <generator uri="https://tdiary.org/" version="">tdiary</generator>
	]
	header << %Q|<subtitle>#{h desc}</subtitle>\n|
	header
end

def makerss_seq( uri, rdfsec )
	%Q|<rdf:li rdf:resource="#{h uri}#{anchor rdfsec.id}"/>\n|
end

def makerss_banner( uri, rdf_image )
	%Q[<image rdf:about="#{h rdf_image}">
	<title>#{h @conf.html_title}</title>
	<url>#{h rdf_image}</url>
	<link>#{h uri}</link>
	</image>
	]
end

def makeatom_desc_shorten( text )
	if @conf['makerss.shortdesc'] then
		@conf['makerss.partial'] = 0.25 unless @conf['makerss.partial']
		len = ( text.size.to_f * @conf['makerss.partial'] ).ceil.to_i
		len = 500 if len > 500
	else
		len = 500
	end
	@conf.shorten( text, len )
end

def feed?
	@makeatom_in_feed
end

def makeatom_body( uri, rdfsec )
	rdf = ""
	if rdfsec.body? then
		rdf = %Q|<entry>\n|
		rdf << %Q|<id>#{h uri}#{anchor rdfsec.id}</id>\n|
		rdf << %Q|<link rel="alternate" type="text/html" href="#{h uri}#{anchor rdfsec.id}" />\n|
		rdf << %Q|<updated>#{h rdfsec.time}</updated>\n|
		a = rdfsec.id.scan( /(\d{4})(\d\d)(\d\d)/ ).flatten.map{|s| s.to_i}
		date = Time::local( *a )
		old_apply_plugin = @conf['apply_plugin']
		@conf['apply_plugin'] = true

		@makeatom_in_feed = true
		subtitle = rdfsec.section['subtitle']
		body_enter = body_enter_proc( date )
		body = apply_plugin( rdfsec.section['body'] )
		body_leave = body_leave_proc( date )
		@makeatom_in_feed = false

		sub = (subtitle || '').sub( /^(\[([^\]]+)\])+ */, '' )
		sub = apply_plugin( sub, true ).strip
		if sub.empty?
			sub = @conf.shorten( remove_tag( body ).strip, 20 )
		end
		rdf << %Q|<title>#{sub}</title>\n|
		rdf << %Q|<author><name>#{h @conf.author_name}</name></author>\n|
		rdfsec.section['category'].each do |category|
			rdf << %Q|<category term="#{h category}" label="#{h category}" />\n|
		end
		desc = remove_tag( body ).strip
		desc.gsub!( /&.*?;/, '' )
		rdf << %Q|<summary>#{h makeatom_desc_shorten( desc )}</summary>\n|
		unless @conf['makerss.hidecontent']
			text = ''
			text << '<h3>' + apply_plugin( subtitle.sub( /^(\[([^\]]+)\])+ */, '' ) ).strip + '</h3>' if subtitle and not subtitle.empty?
			text << body_enter
			text << body
			text << body_leave
			unless text.empty?
				uri = @conf.index.dup
				uri[0, 0] = base_url unless %r|^https?://|i =~ uri
				uri.gsub!( %r|/\./|, '/' )
				text = absolutify( text, uri )
				rdf << %Q|<content type="html">|
				content = text
				unless @conf['makerss.comment_link']
					ymd = date.strftime( "%Y%m%d" )
					content << %Q|\n<p><a href="#{h uri}#{anchor "#{ymd}c"}">#{comment_new}</a></p>|
				end
				rdf << h( content )
				rdf << %Q|</content>\n|
			end
		end

		@conf['apply_plugin'] = old_apply_plugin
		rdf << "</entry>\n"
	else # TSUKKOMI
		rdf = %Q|<entry>\n|
		rdf << %Q|<link href="#{h uri}#{anchor rdfsec.id}" />\n|
		rdf << %Q|<id>#{h uri}#{anchor rdfsec.id}</id>\n|
		rdf << %Q|<updated>#{h rdfsec.time}</updated>\n|
		rdf << %Q|<title>#{makerss_tsukkomi_label( rdfsec.id )} (#{h rdfsec.section['name']})</title>\n|
		rdf << %Q|<author><name>#{h rdfsec.section['name']}</name></author>\n|
		text = rdfsec.section['body']
		rdf << %Q|<summary>#{h makeatom_desc_shorten( text )}</summary>\n|
		unless @conf['makerss.hidecontent']
			rdf << %Q|<content type="html">#{h text.make_link.gsub( /\n/, '<br>' ).gsub( /<br><br>\Z/, '' )}</content>\n|
		end
		rdf << "</entry>\n"
	end
	rdf
end

def makeatom_footer
	"</feed>\n"
end

add_update_proc do
	makeatom_update unless @cgi.params['makerss_update'][0] == 'false'
end

add_header_proc {
	html = ''
	@makeatom_files.each do |rss|
		next unless rss.url
		html << %Q|\t<link rel="alternate" type="application/atom+xml" title="Atom#{h rss.title}" href="#{h rss.url}">\n|
	end
	html
}

# hidecontent shortdesc commnet_lint no_comments
# 
# add_conf_proc( 'makeatom', @makeatom_conf_label, 'update' ) do
# 	if @mode == 'saveconf' then
# 		%w( hidecontent shortdesc comment_link no_comments).each do |s|
# 			item = "makeatom.#{s}"
# 			@conf[item] = ( 't' == @cgi.params[item][0] )
# 		end
# 	end
# 
# 	@makeatom_files.each do |rss|
# 		if rss.class == MakeAtomFull then
# 			@makeatom_full = rss
# 		elsif rss.class == MakeAtomNoComments
# 			@makeatom_no_comments = rss
# 		end
# 	end
# 	makeatom_conf_html
# end

# add_edit_proc do
# 	checked = if @cgi.params['makerss_update'][0] == 'false' then
# 		' checked'
# 	elsif @date < (Time::now - 30*24*60*60) # older over a month
# 		' checked'
# 	else
# 		''
# 	end
# 	<<-HTML
# 	<div class="makerss"><label for="makerss_update">
# 	<input type="checkbox" id="makerss_update" name="makerss_update" value="false"#{checked} tabindex="390">
# 	#{@makerss_edit_label}
# 	</label></div>
# 	HTML
# end

add_startup_proc do
	makeatom_update
end

def replace_entities( text )
	unless @xml_entity_table then
		@xml_entity_table = {
			'&nbsp;' => '&#160;',
			'&iexcl;' => '&#161;',
			'&cent;' => '&#162;',
			'&pound;' => '&#163;',
			'&curren;' => '&#164;',
			'&yen;' => '&#165;',
			'&brvbar;' => '&#166;',
			'&sect;' => '&#167;',
			'&uml;' => '&#168;',
			'&copy;' => '&#169;',
			'&ordf;' => '&#170;',
			'&laquo;' => '&#171;',
			'&not;' => '&#172;',
			'&shy;' => '&#173;',
			'&reg;' => '&#174;',
			'&macr;' => '&#175;',
			'&deg;' => '&#176;',
			'&plusmn;' => '&#177;',
			'&sup2;' => '&#178;',
			'&sup3;' => '&#179;',
			'&acute;' => '&#180;',
			'&micro;' => '&#181;',
			'&para;' => '&#182;',
			'&middot;' => '&#183;',
			'&cedil;' => '&#184;',
			'&sup1;' => '&#185;',
			'&ordm;' => '&#186;',
			'&raquo;' => '&#187;',
			'&frac14;' => '&#188;',
			'&frac12;' => '&#189;',
			'&frac34;' => '&#190;',
			'&iquest;' => '&#191;',
			'&Agrave;' => '&#192;',
			'&Aacute;' => '&#193;',
			'&Acirc;' => '&#194;',
			'&Atilde;' => '&#195;',
			'&Auml;' => '&#196;',
			'&Aring;' => '&#197;',
			'&Aelig;' => '&#198;',
			'&Ccedil;' => '&#199;',
			'&Egrave;' => '&#200;',
			'&Eacute;' => '&#201;',
			'&Ecirc;' => '&#202;',
			'&Euml;' => '&#203;',
			'&Igrave;' => '&#204;',
			'&Iacute;' => '&#205;',
			'&Icirc;' => '&#206;',
			'&Iuml;' => '&#207;',
			'&ETH;' => '&#208;',
			'&Ntilde;' => '&#209;',
			'&Ograve;' => '&#210;',
			'&Oacute;' => '&#211;',
			'&Ocirc;' => '&#212;',
			'&Otilde;' => '&#213;',
			'&Ouml;' => '&#214;',
			'&times;' => '&#215;',
			'&Oslash;' => '&#216;',
			'&Ugrave;' => '&#217;',
			'&Uacute;' => '&#218;',
			'&Ucirc;' => '&#219;',
			'&Uuml;' => '&#220;',
			'&Yacute;' => '&#221;',
			'&THORN;' => '&#222;',
			'&szlig;' => '&#223;',
			'&agrave;' => '&#224;',
			'&aacute;' => '&#225;',
			'&acirc;' => '&#226;',
			'&atilde;' => '&#227;',
			'&auml;' => '&#228;',
			'&aring;' => '&#229;',
			'&aelig;' => '&#230;',
			'&ccedil;' => '&#231;',
			'&egrave;' => '&#232;',
			'&eacute;' => '&#233;',
			'&ecirc;' => '&#234;',
			'&euml;' => '&#235;',
			'&igrave;' => '&#236;',
			'&iacute;' => '&#237;',
			'&icirc;' => '&#238;',
			'&iuml;' => '&#239;',
			'&eth;' => '&#240;',
			'&ntilde;' => '&#241;',
			'&ograve;' => '&#242;',
			'&oacute;' => '&#243;',
			'&ocirc;' => '&#244;',
			'&otilde;' => '&#245;',
			'&ouml;' => '&#246;',
			'&divide;' => '&#247;',
			'&oslash;' => '&#248;',
			'&ugrave;' => '&#249;',
			'&uacute;' => '&#250;',
			'&ucirc;' => '&#251;',
			'&uuml;' => '&#252;',
			'&yacute;' => '&#253;',
			'&thorn;' => '&#254;',
			'&yuml;' => '&#255;',
			'&OElig;' => '&#338;',
			'&oelig;' => '&#339;',
			'&Scaron;' => '&#352;',
			'&scaron;' => '&#353;',
			'&Yuml;' => '&#376;',
			'&circ;' => '&#710;',
			'&tilde;' => '&#732;',
			'&ensp;' => '&#8194;',
			'&emsp;' => '&#8195;',
			'&thinsp;' => '&#8201;',
			'&zwnj;' => '&#8204;',
			'&zwj;' => '&#8205;',
			'&lrm;' => '&#8206;',
			'&rlm;' => '&#8207;',
			'&ndash;' => '&#8211;',
			'&mdash;' => '&#8212;',
			'&lsquo;' => '&#8216;',
			'&rsquo;' => '&#8217;',
			'&sbquo;' => '&#8218;',
			'&ldquo;' => '&#8220;',
			'&rdquo;' => '&#8221;',
			'&bdquo;' => '&#8222;',
			'&dagger;' => '&#8224;',
			'&Dagger;' => '&#8225;',
			'&permil;' => '&#8240;',
			'&lsaquo;' => '&#8249;',
			'&rsaquo;' => '&#8250;',
			'&euro;' => '&#8364;',
			'&fnof;' => '&#402;',
			'&Alpha;' => '&#913;',
			'&Beta;' => '&#914;',
			'&Gamma;' => '&#915;',
			'&Delta;' => '&#916;',
			'&Epsilon;' => '&#917;',
			'&Zeta;' => '&#918;',
			'&Eta;' => '&#919;',
			'&Theta;' => '&#920;',
			'&Iota;' => '&#921;',
			'&Kappa;' => '&#922;',
			'&Lambda;' => '&#923;',
			'&Mu;' => '&#924;',
			'&Nu;' => '&#925;',
			'&Xi;' => '&#926;',
			'&Omicron;' => '&#927;',
			'&Pi;' => '&#928;',
			'&Rho;' => '&#929;',
			'&Sigma;' => '&#931;',
			'&Tau;' => '&#932;',
			'&Upsilon;' => '&#933;',
			'&Phi;' => '&#934;',
			'&Chi;' => '&#935;',
			'&Psi;' => '&#936;',
			'&Omega;' => '&#937;',
			'&alpha;' => '&#945;',
			'&beta;' => '&#946;',
			'&gamma;' => '&#947;',
			'&delta;' => '&#948;',
			'&epsilon;' => '&#949;',
			'&zeta;' => '&#950;',
			'&eta;' => '&#951;',
			'&theta;' => '&#952;',
			'&iota;' => '&#953;',
			'&kappa;' => '&#954;',
			'&lambda;' => '&#955;',
			'&mu;' => '&#956;',
			'&nu;' => '&#957;',
			'&xi;' => '&#958;',
			'&omicron;' => '&#959;',
			'&pi;' => '&#960;',
			'&rho;' => '&#961;',
			'&sigmaf;' => '&#962;',
			'&sigma;' => '&#963;',
			'&tau;' => '&#964;',
			'&upsilon;' => '&#965;',
			'&phi;' => '&#966;',
			'&chi;' => '&#967;',
			'&psi;' => '&#968;',
			'&omega;' => '&#969;',
			'&thetasym;' => '&#977;',
			'&upsih;' => '&#978;',
			'&piv;' => '&#982;',
			'&bull;' => '&#8226;',
			'&hellip;' => '&#8230;',
			'&prime;' => '&#8242;',
			'&Prime;' => '&#8243;',
			'&oline;' => '&#8254;',
			'&frasl;' => '&#8260;',
			'&weierp;' => '&#8472;',
			'&image;' => '&#8465;',
			'&real;' => '&#8476;',
			'&trade;' => '&#8482;',
			'&alefsym;' => '&#8501;',
			'&larr;' => '&#8592;',
			'&rarr;' => '&#8594;',
			'&darr;' => '&#8595;',
			'&harr;' => '&#8596;',
			'&crarr;' => '&#8629;',
			'&lArr;' => '&#8656;',
			'&uArr;' => '&#8657;',
			'&rArr;' => '&#8658;',
			'&dArr;' => '&#8659;',
			'&hArr;' => '&#8660;',
			'&forall;' => '&#8704;',
			'&part;' => '&#8706;',
			'&exist;' => '&#8707;',
			'&empty;' => '&#8709;',
			'&nabla;' => '&#8711;',
			'&isin;' => '&#8712;',
			'&notin;' => '&#8713;',
			'&ni;' => '&#8715;',
			'&prod;' => '&#8719;',
			'&sum;' => '&#8721;',
			'&minus;' => '&#8722;',
			'&lowast;' => '&#8727;',
			'&radic;' => '&#8730;',
			'&prop;' => '&#8733;',
			'&infin;' => '&#8734;',
			'&ang;' => '&#8736;',
			'&and;' => '&#8743;',
			'&or;' => '&#8744;',
			'&cap;' => '&#8745;',
			'&cup;' => '&#8746;',
			'&int;' => '&#8747;',
			'&there4;' => '&#8756;',
			'&sim;' => '&#8764;',
			'&cong;' => '&#8773;',
			'&asymp;' => '&#8776;',
			'&ne;' => '&#8800;',
			'&equiv;' => '&#8801;',
			'&le;' => '&#8804;',
			'&ge;' => '&#8805;',
			'&sub;' => '&#8834;',
			'&sup;' => '&#8835;',
			'&nsub;' => '&#8836;',
			'&sube;' => '&#8838;',
			'&supe;' => '&#8839;',
			'&oplus;' => '&#8853;',
			'&otimes;' => '&#8855;',
			'&perp;' => '&#8869;',
			'&sdot;' => '&#8901;',
			'&lceil;' => '&#8968;',
			'&rceil;' => '&#8969;',
			'&lfloor;' => '&#8970;',
			'&rfloor;' => '&#8971;',
			'&lang;' => '&#9001;',
			'&rang;' => '&#9002;',
			'&loz;' => '&#9674;',
			'&spades;' => '&#9824;',
			'&clubs;' => '&#9827;',
			'&hearts;' => '&#9829;',
			'&diams;' => '&#9830;'
		}
	end
	text.gsub( /&[a-z]+;/im ) do |e|
		@xml_entity_table[e] || e
	end
end

# Copied from below which includes some tests
# http://github.com/zunda/ruby-absolutify/tree/master
def absolutify(html, baseurl)
	@@_absolutify_attr_regexp ||= Hash.new
	baseuri = URI.parse(baseurl)
	r = html.gsub(%r|<\S[^>]*/?>|) do |tag|
		type = tag.scan(/\A<(\S+)/)[0][0].downcase
		if attr = {'a' => 'href', 'img' => 'src'}[type]
			@@_absolutify_attr_regexp[attr] ||= %r|(.*#{attr}\s*=\s*)(['"]?)([^\2>]+?)(\2.*)|im
			m = tag.match(@@_absolutify_attr_regexp[attr])
			unless m.nil?
				prefix = m[1] + m[2]
				location = m[3]
				postfix = m[4]
				begin
					uri = URI.parse(location)
					if uri.relative?
						location = (baseuri + location).to_s
					elsif not uri.host and uri.path
						path = uri.path
						path += '?' + uri.query if uri.query
						path += '#' + uri.fragment if uri.fragment
						location = (baseuri + path).to_s
					end
					tag = prefix + location + postfix
				rescue URI::InvalidURIError
				end
			end
		end
		tag
	end
	return r
end

# Local Variables:
# mode: ruby
# indent-tabs-mode: t
# tab-width: 3
# ruby-indent-level: 3
# End:
