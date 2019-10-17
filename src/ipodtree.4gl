-- A Genero Tree Demo
-- Features: TreeView / SAX Handling / Sockets
--
-- The program can read an iTunes(tm) Music Library xml files import into a
-- database.
-- By default the program will work without a database.
-- To use a database you must setup your fglprofile entries for your choosen
-- database and set IPOD_DBNAME = to the name of that database.

IMPORT os
IMPORT util
IMPORT com
IMPORT FGL g2_lib
IMPORT FGL g2_aui
IMPORT FGL g2_about
IMPORT FGL g2_appInfo

CONSTANT C_PRGVER = "3.1"
CONSTANT C_PRGDESC = "TreeView Demo"
CONSTANT C_PRGAUTH = "Neil J.Martin"
CONSTANT C_PRGICON = "logo_dark"

CONSTANT IDLE_TIME = 300

DEFINE xml_d om.domDocument
DEFINE xml_r om.domNode

TYPE t_song RECORD
	sortby VARCHAR(140),
	genre VARCHAR(40),
	artist VARCHAR(40),
	album VARCHAR(40),
	year CHAR(4),
	discno SMALLINT,
	trackno SMALLINT,
	title VARCHAR(40),
	dur CHAR(10),
	file VARCHAR(100),
	play_count SMALLINT,
	rating SMALLINT
END RECORD

TYPE t_tree RECORD
	name STRING,
	year CHAR(4),
	pid STRING,
	id STRING,
	img STRING,
	expanded BOOLEAN,
	artist_name STRING
END RECORD

TYPE t_tracks RECORD
	genre_key INTEGER,
	artist_key INTEGER,
	album_key INTEGER,
	trackno SMALLINT,
	title STRING,
	dur CHAR(10),
	file VARCHAR(100),
	play_count SMALLINT,
	rating STRING,
	image STRING
END RECORD

DEFINE song_a DYNAMIC ARRAY OF t_song
DEFINE tree_a DYNAMIC ARRAY OF t_tree
DEFINE tracks_a DYNAMIC ARRAY OF t_tracks
DEFINE sel_tracks_a DYNAMIC ARRAY OF t_tracks
DEFINE genre_a DYNAMIC ARRAY OF RECORD
	genre STRING,
	genre_key INTEGER,
	artist_cnt INTEGER
END RECORD
DEFINE artist_a DYNAMIC ARRAY OF RECORD
--		genre STRING,
	artist STRING,
	artist_key INTEGER,
	album_cnt INTEGER
END RECORD
DEFINE album_a DYNAMIC ARRAY OF RECORD
	artist STRING,
	album_key INTEGER,
	artist_key INTEGER,
	genre_key INTEGER,
	album STRING,
	genre STRING,
	year CHAR(4)
END RECORD

DEFINE f om.SaxDocumentHandler

DEFINE t_sec, t_min, t_hr, t_day INTEGER
DEFINE m_getAlbumArt, workFromDB BOOLEAN

DEFINE m_album_art_artist DYNAMIC ARRAY OF RECORD
	score SMALLINT,
	id STRING,
	name STRING
END RECORD
DEFINE m_album_art_cover STRING
DEFINE m_musicbrainz_url STRING
DEFINE m_mb STRING
DEFINE m_artist, m_prev_artist, m_album, m_prev_album STRING
DEFINE m_appInfo g2_appInfo.appInfo
MAIN
	DEFINE l_file STRING

	OPTIONS ON CLOSE APPLICATION CALL tidyup

	CALL m_appInfo.progInfo(C_PRGDESC, C_PRGAUTH, C_PRGVER, C_PRGICON)
	CALL g2_lib.g2_init(ARG_VAL(1), "ipodtree")

	CALL ui.Interface.setText(C_PRGDESC)

	OPEN FORM win FROM "ipodtree"
	DISPLAY FORM win
	CALL ui.window.getCurrent().setText("Loading, please wait ...")
	CALL ui.interface.refresh()

	LET l_file = "iTunes Music Library.xml"
	LET workFromDB = FALSE

	--CALL gldb_connect(NULL)
	--LET workFromDB = TRUE

-- This options loads the original iTunes .xml file using a SAX Handler.
-- This creates a much similer xml file called songs.xml

	IF arg_val(2) = "LOAD" THEN
		CALL openLibrary(l_file)
	ELSE
		IF workFromDB THEN
			CALL db_read()
		ELSE
			LET l_file = "../etc/music.xml"
			IF NOT os.path.exists(l_file) THEN
				LET l_file = "../ipodTree/etc/music.xml"
			END IF
			IF NOT os.path.exists(l_file) THEN
				CALL g2_lib.g2_errPopup(
						% "'" || l_file || "' Doesn't Exist, try running again like this\nfglrun ipod.42r LOAD")
				EXIT PROGRAM
			END IF
			CALL openXML(l_file)
			CALL loadMusic()
		END IF
	END IF

	CALL song_a.clear() -- This array not needed now, just used to create tree from xml.

	LET m_getAlbumArt = TRUE
	CALL dispInfo()
	CALL mainDialog()
	CALL g2_lib.g2_exitProgram(0, % "Program Finished")
END MAIN
--------------------------------------------------------------------------------
FUNCTION mainDialog()
	DEFINE r_search, t_search, a_search, l_ret STRING
	DEFINE n om.DomNode
	LET m_prev_artist = "."
	LET m_prev_album = "."
	DISPLAY CURRENT, ": Starting main dialog."
	DISPLAY "noimage" TO album_art
	CALL ui.window.getCurrent().setText("My Genero Music Tree Demo")

	DIALOG ATTRIBUTES(UNBUFFERED)
		DISPLAY ARRAY tree_a TO tree.*
			BEFORE ROW
				IF tree_a.getLength() > 0 THEN
					CALL loadTracks(tree_a[arr_curr()].id)
				END IF
				IF tree_a[arr_curr()].img IS NOT NULL THEN -- artist or album
					LET m_artist = tree_a[arr_curr()].artist_name
					IF m_artist != m_prev_artist THEN
						LET m_mb = "Artist:", m_artist, " (", getArtistID(m_artist), ")"
						LET m_album = "."
					END IF
					LET m_prev_artist = m_artist
					IF tree_a[arr_curr()].img != "user" THEN -- it's an album
						LET m_album = tree_a[arr_curr()].name
						IF m_prev_album != m_album AND m_getAlbumArt THEN
							DISPLAY getAlbumArtURL(m_album) TO album_art
						END IF
						LET m_prev_album = m_album
						--CALL ui.interface.refresh()
					END IF
				END IF
				DISPLAY CURRENT, ":Current Row:", arr_curr(), " Artist:", m_artist, " Album:", m_album

			ON ACTION search
				NEXT FIELD search
			ON UPDATE
				CALL upd_tree_item(arr_curr(), scr_line())
		END DISPLAY

		INPUT BY NAME r_search, a_search, t_search, m_mb ATTRIBUTES(WITHOUT DEFAULTS = TRUE)
			ON ACTION t_search
				IF t_search.getLength() > 0 THEN
					IF workFromDB THEN
						CALL t_searchDB(t_search)
					ELSE
						CALL t_searchARR(t_search)
					END IF
				END IF
			ON ACTION a_search
				IF a_search.getLength() > 0 THEN
					IF workFromDB THEN
						CALL al_searchDB(a_search)
					ELSE
						CALL al_searchARR(a_search)
					END IF
				END IF
			ON ACTION r_search
				IF r_search.getLength() > 0 THEN
					IF workFromDB THEN
						CALL ar_searchDB(r_search)
					ELSE
						CALL ar_searchARR(r_search)
					END IF
				END IF
		END INPUT

		DISPLAY ARRAY sel_tracks_a TO tracks.*
			ON ACTION search
				NEXT FIELD r_search
			BEFORE ROW
				IF arr_curr() > 0 THEN
					CALL dispRowDetails(
							sel_tracks_a[arr_curr()].genre_key,
							sel_tracks_a[arr_curr()].artist_key,
							sel_tracks_a[arr_curr()].album_key)
				END IF
		END DISPLAY

		INPUT BY NAME m_getAlbumArt ATTRIBUTES(WITHOUT DEFAULTS = TRUE)
			ON ACTION search
				NEXT FIELD r_search
			ON CHANGE m_getAlbumArt
				IF NOT m_getAlbumArt THEN
					DISPLAY "noimage" TO album_art
				END IF
		END INPUT

		BEFORE DIALOG
			CALL DIALOG.setSelectionMode("tree", TRUE)
			LET n = ui.Interface.getRootNode()

		ON ACTION showbig
			IF m_album_art_cover IS NOT NULL THEN
				CALL show_big_cover(m_album_art_cover)
			END IF
		ON ACTION musicbrainz
			DISPLAY "URL: ", m_musicbrainz_url
			IF m_musicbrainz_url IS NOT NULL THEN
				CALL ui.Interface.frontCall("standard", "launchURL", m_musicbrainz_url, [l_ret])
				DISPLAY "launchURL Ret:", l_ret
			END IF

		ON ACTION open
			CALL openLibrary(NULL)
		ON ACTION close
			EXIT DIALOG
		ON ACTION about
			CALL g2_about.g2_about(m_appInfo)
		ON ACTION quit
			EXIT DIALOG

		ON ACTION dump
			CALL n.writeXml("aui.xml")

		ON IDLE IDLE_TIME
			DISPLAY "IDLE Time reached."
			EXIT DIALOG
	END DIALOG

	DISPLAY CURRENT, ": Program Finished."
END FUNCTION
FUNCTION upd_tree_item(l_row, l_scr)
	DEFINE l_row, l_scr SMALLINT
	INPUT tree_a[l_row].name FROM tree[l_scr].name
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION dispInfo()

	LET t_hr = t_sec / 3600
	LET t_min = t_hr / 60
	LET t_sec = t_hr - (t_min * 60)
	LET t_day = t_hr / 24
	LET t_hr = t_hr - (t_day * 24)

	DISPLAY genre_a.getLength() TO genres
	DISPLAY artist_a.getLength() TO artists
	DISPLAY album_a.getLength() TO albums
	DISPLAY tracks_a.getLength() TO tracks
	DISPLAY "Total Play Time: "
					|| t_day
					|| " Days "
					|| t_hr
					|| " hours "
					|| t_min
					|| " minutes "
					|| t_sec
					|| " seconds"
			TO playtime

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION openLibrary(file)
	DEFINE file STRING

	IF file IS NULL THEN
		CALL ui.interface.frontCall(
				"standard", "openfile", ["", "iTunes Library", "*.xml", "Choose a Library"], file)
	END IF
	IF file IS NULL THEN
		MESSAGE "Cancelled."
		RETURN
	END IF

	IF NOT os.path.exists(file) THEN
		CALL g2_lib.g2_errPopup(% "'" || file || "' Doesn't Exist, can't do load")
		RETURN
	END IF

	CALL ui.window.getCurrent().setText("Loading, please wait ...")
	CALL ui.interface.refresh()

	LET f = om.SaxDocumentHandler.createForName("ipod_sax")
	CALL f.readXmlFile(file)

	CALL loadSongs()

	IF workFromDB THEN
		CALL db_mk_tab()
		CALL db_load_tab()
	END IF
	CALL dispInfo()

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION openXML(file)
	DEFINE file STRING

	DISPLAY CURRENT, ": Opening " || file || " ..."
	LET xml_d = om.domDocument.createFromXMLFile(file)
	IF xml_d IS NULL THEN
		CALL g2_lib.g2_errPopup(
				% "Failed to open '" || file || "'!\nTry running like this: fglrun ipod.42r LOAD")
		EXIT PROGRAM
	END IF
	LET xml_r = xml_d.getDocumentElement()
	IF xml_r IS NULL THEN
		CALL g2_lib.g2_errPopup(% "Failed to get root node!")
		EXIT PROGRAM
	END IF

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION t_searchARR(what)
	DEFINE tmp, what STRING
	DEFINE x INTEGER

	CALL showBranch(0, 0, 0, FALSE)
	CALL sel_tracks_a.clear()
	FOR x = 1 TO tracks_a.getLength()
		LET tmp = tracks_a[x].title.toUpperCase()
		IF tmp.getIndexOf(what.toUpperCase(), 1) > 0 THEN
			CALL setSelTrack(x)
		END IF
	END FOR
	DISPLAY sel_tracks_a.getLength() TO nooftracks
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION ar_searchARR(what)
	DEFINE tmp, what STRING
	DEFINE x, y INTEGER

	MESSAGE "Searching for Artist matching '" || what || "'"
	CALL showBranch(0, 0, 0, FALSE)
	CALL sel_tracks_a.clear()
	FOR x = 1 TO artist_a.getLength()
		LET tmp = artist_a[x].artist.toUpperCase()
		IF tmp.getIndexOf(what.toUpperCase(), 1) > 0 THEN
			FOR y = 1 TO tracks_a.getLength()
				IF tracks_a[y].artist_key != artist_a[x].artist_key THEN
					CONTINUE FOR
				END IF
				CALL setSelTrack(y)
			END FOR
			CALL showBranch(0, artist_a[x].artist_key, 0, TRUE)
		END IF
	END FOR
	DISPLAY sel_tracks_a.getLength() TO nooftracks
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION al_searchARR(what)
	DEFINE tmp, what STRING
	DEFINE x, y INTEGER

	CALL showBranch(0, 0, 0, FALSE)
	CALL sel_tracks_a.clear()
	FOR x = 1 TO album_a.getLength()
		LET tmp = album_a[x].album.toUpperCase()
		IF tmp.getIndexOf(what.toUpperCase(), 1) > 0 THEN
			FOR y = 1 TO tracks_a.getLength()
				IF tracks_a[y].album_key != album_a[x].album_key THEN
					CONTINUE FOR
				END IF
				CALL setSelTrack(y)
			END FOR
			CALL showBranch(0, artist_a[x].artist_key, album_a[x].album_key, TRUE)
		END IF
	END FOR
	DISPLAY sel_tracks_a.getLength() TO nooftracks
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION t_searchDB(what)
	DEFINE what STRING

	CALL showBranch(0, 0, 0, FALSE)
	CALL sel_tracks_a.clear()
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION ar_searchDB(what)
	DEFINE what STRING

	CALL showBranch(0, 0, 0, FALSE)
	CALL sel_tracks_a.clear()
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION al_searchDB(what)
	DEFINE what STRING

	CALL showBranch(0, 0, 0, FALSE)
	CALL sel_tracks_a.clear()
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION loadMusic()
	DEFINE x, y, z, k, g INTEGER
	DEFINE xml_g, xml_ar, xml_al, xml_tr om.domNode
	DEFINE nl, nl2, nl3 om.nodeList

	CALL genre_a.clear()
	CALL artist_a.clear()
	CALL album_a.clear()
	CALL tracks_a.clear()

	DISPLAY CURRENT, ": Loading from XML into array ..."
	LET nl = xml_r.selectByTagName("Genre")
	LET g = 0
	FOR x = 1 TO nl.getlength()
		LET xml_g = nl.item(x)
		LET g = g + 1
		LET genre_a[g].genre = xml_g.getAttribute("name")
		LET genre_a[g].genre_key = g
		LET nl2 = xml_g.selectByTagName("Artist")
		LET genre_a[g].artist_cnt = nl2.getLength()
		FOR y = 1 TO nl2.getLength()
			LET xml_ar = nl2.item(y)
			LET k = xml_ar.getAttribute("artist_key")
			LET artist_a[k].artist = xml_ar.getAttribute("name")
			LET artist_a[k].artist_key = k
			LET nl3 = xml_ar.selectByTagName("Album")
			FOR z = 1 TO nl3.getLength()
				LET xml_al = nl3.item(z)
				LET k = xml_al.getAttribute("album_key")
				LET album_a[k].album = xml_al.getAttribute("name")
				LET album_a[k].album_key = k
				LET album_a[k].artist_key = xml_al.getAttribute("artist_key")
				LET album_a[k].genre_key = xml_al.getAttribute("genre_key")
				LET album_a[k].year = xml_al.getAttribute("year")
				LET album_a[k].genre = xml_g.getAttribute("name")
				LET album_a[k].artist = xml_ar.getAttribute("name")
			END FOR
		END FOR
	END FOR

	LET nl = xml_r.selectByTagName("Track")
	FOR x = 1 TO nl.getlength()
		LET xml_tr = nl.item(x)
		LET tracks_a[x].dur = xml_tr.getAttribute("dur")
		LET tracks_a[x].genre_key = xml_tr.getAttribute("genre_key")
		LET tracks_a[x].album_key = xml_tr.getAttribute("album_key")
		LET tracks_a[x].artist_key = xml_tr.getAttribute("artist_key")
		LET tracks_a[x].title = xml_tr.getAttribute("title")
		LET tracks_a[x].trackno = xml_tr.getAttribute("trackno")
		LET tracks_a[x].file = xml_tr.getAttribute("file")
		LET tracks_a[x].play_count = xml_tr.getAttribute("play_count")
		LET tracks_a[x].rating = xml_tr.getAttribute("rating")
		LET t_min = t_min + tracks_a[x].dur[1, 2]
		LET t_sec = t_sec + tracks_a[x].dur[4, 5]
	END FOR
	CALL buildTree()
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION set_xml_n(n) -- Called from SAX Handler.
	DEFINE n om.domNode

	LET xml_r = n

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION loadSongs()
	DEFINE x, gk, ark, alk INTEGER
	DEFINE trck, c om.domNode
	DEFINE tim, hr, minu, sec, navg, pavg INTEGER
	DEFINE song t_song
--	DEFINE xml_d om.domDocument
	DEFINE xml_g, xml_ar, xml_al, xml_tr om.domNode
	DEFINE nl om.nodeList

	CALL song_a.clear()
	CALL genre_a.clear()
	CALL artist_a.clear()
	CALL album_a.clear()
	CALL tracks_a.clear()

	LET t_sec = 0
	LET t_min = 0
	LET t_hr = 0
	LET t_day = 0

	DISPLAY CURRENT, ": Nodes:", xml_r.getChildCount(), ":", xml_r.getTagName()

	LET trck = xml_r.getFirstChild()
	LET x = 0
	DISPLAY CURRENT, ": Loading from XML into array & sorting ..."

	CALL g2_aui.g2_progBar(1, 100, "Processing XML - Phase 1 of 3")
	LET pavg = 0
	WHILE trck IS NOT NULL
		LET navg = ((x / song_a.getLength()) * 100)
		IF pavg != navg THEN
			LET pavg = navg
			CALL g2_aui.g2_progBar(2, pavg, "")
		END IF
		LET song.title = trck.getAttribute("name")
		IF song.title IS NULL OR song.title = " " THEN
			LET trck = trck.getNext()
			CONTINUE WHILE
		END IF
		LET song.artist = trck.getAttribute("artist")
		IF song.artist IS NULL OR length(song.artist CLIPPED) < 1 THEN
			LET song.artist = "(null)"
		END IF
		LET song.album = trck.getAttribute("album")
		IF song.album IS NULL OR length(song.album CLIPPED) < 1 THEN
			LET song.album = "(null)"
		END IF
		LET song.genre = trck.getAttribute("genre")
		IF song.genre IS NULL OR length(song.genre CLIPPED) < 1 THEN
			LET song.genre = "(null)"
		END IF
		LET song.discno = trck.getAttribute("disc_number")
		IF song.discno IS NULL THEN
			LET song.discno = 0
		END IF
		LET song.trackno = trck.getAttribute("track_number")
		IF song.trackno IS NULL THEN
			LET song.trackno = 0
		END IF
		LET song.year = trck.getAttribute("year")
		LET song.play_count = trck.getAttribute("play_count")
		LET song.rating = trck.getAttribute("rating")
		LET tim = trck.getAttribute("total_time")
		IF tim IS NOT NULL THEN
			LET hr = tim / 1000
			LET minu = hr / 60
			LET sec = hr - (minu * 60)
			LET song.dur = minu USING "&&", ":", sec USING "&&"
			LET t_sec = t_sec + (tim / 1000)
			LET t_min = t_min + minu
		END IF
		LET c = trck.getFirstChild()
		IF c IS NOT NULL THEN
			LET song.file = c.getAttribute("@chars")
		END IF
		CALL sortSongs(song.*)
		LET trck = trck.getNext()
	END WHILE

	DISPLAY CURRENT, ": Building Sub Arrays & music.xml ..."

	LET xml_d = om.domdocument.create("Music")
	LET xml_r = xml_d.getdocumentelement()
	CALL g2_aui.g2_progBar(3, 0, "")
	CALL g2_aui.g2_progBar(1, 100, "Processing XML - Phase 2 of 3")
	LET pavg = 0
	FOR x = 1 TO song_a.getLength()
		LET navg = ((x / song_a.getLength()) * 100)
		IF pavg != navg THEN
			LET pavg = navg
			CALL g2_aui.g2_progBar(2, pavg, "")
		END IF
		FOR gk = 1 TO genre_a.getLength()
			IF genre_a[gk].genre = song_a[x].genre THEN
				EXIT FOR
			END IF
		END FOR
		IF gk > genre_a.getLength() THEN
			LET genre_a[genre_a.getLength() + 1].genre = song_a[x].genre
			LET genre_a[genre_a.getLength()].genre_key = gk
			LET xml_g = xml_r.createChild("Genre")
			CALL xml_g.setAttribute("name", genre_a[genre_a.getLength()].genre)
			CALL xml_g.setAttribute("genre_key", genre_a[genre_a.getLength()].genre_key)
		END IF
		FOR ark = 1 TO artist_a.getLength()
			IF artist_a[ark].artist = song_a[x].artist THEN
				EXIT FOR
			END IF
		END FOR
		IF ark > artist_a.getLength() THEN
			LET artist_a[artist_a.getLength() + 1].artist = song_a[x].artist
--			LET artist_a[ artist_a.getLength()].genre = song_a[x].genre
			LET artist_a[artist_a.getLength()].artist_key = ark
			LET xml_ar = xml_g.createChild("Artist")
			CALL xml_ar.setAttribute("name", artist_a[artist_a.getLength()].artist)
			CALL xml_ar.setAttribute("artist_key", artist_a[artist_a.getLength()].artist_key)
			CALL xml_ar.setAttribute("genre_key", gk)
		END IF
		FOR alk = 1 TO album_a.getLength()
			IF album_a[alk].album = song_a[x].album THEN
				EXIT FOR
			END IF
		END FOR
		IF alk > album_a.getLength() THEN
			LET album_a[album_a.getLength() + 1].artist = song_a[x].artist
			LET album_a[album_a.getLength()].album = song_a[x].album
			LET album_a[album_a.getLength()].year = song_a[x].year
			LET album_a[album_a.getLength()].genre = song_a[x].genre
			LET album_a[album_a.getLength()].album_key = alk
			LET album_a[album_a.getLength()].artist_key = ark
			LET nl = xml_g.selectbypath("//Artist[@artist_key='" || ark || "']")
			IF nl.getlength() > 0 THEN
				LET xml_ar = nl.item(1)
			ELSE
				LET nl = xml_r.selectbypath("//Artist[@artist_key='" || ark || "']")
				IF nl.getlength() > 0 THEN
					LET xml_ar = xml_g.createChild("Artist")
					CALL xml_ar.setAttribute("name", album_a[album_a.getLength()].artist)
					CALL xml_ar.setAttribute("artist_key", ark)
					CALL xml_ar.setAttribute("genre_key", gk)
				ELSE
					DISPLAY "Failed to find Artist!   //Artist[@artist_key='" || ark || "']"
				END IF
			END IF
			LET xml_al = xml_ar.createChild("Album")
			CALL xml_al.setAttribute("name", album_a[album_a.getLength()].album)
			CALL xml_al.setAttribute("album_key", album_a[album_a.getLength()].album_key)
			CALL xml_al.setAttribute("year", song_a[x].year)
			CALL xml_al.setAttribute("artist_key", ark)
			CALL xml_al.setAttribute("genre_key", gk)
		END IF
		LET xml_tr = xml_ar.createChild("Track")
		CALL xml_tr.setAttribute("album_key", alk)
		CALL xml_tr.setAttribute("artist_key", ark)
		CALL xml_tr.setAttribute("genre_key", gk)
		CALL xml_tr.setAttribute("title", song_a[x].title)
		CALL xml_tr.setAttribute("trackno", song_a[x].trackno)
		CALL xml_tr.setAttribute("dur", song_a[x].dur CLIPPED)
		CALL xml_tr.setAttribute("file", song_a[x].file CLIPPED)
		CALL xml_tr.setAttribute("play_count", song_a[x].play_count)
		CALL xml_tr.setAttribute("rating", song_a[x].rating)
		LET tracks_a[tracks_a.getLength() + 1].genre_key = gk
		LET tracks_a[tracks_a.getLength()].artist_key = ark
		LET tracks_a[tracks_a.getLength()].album_key = alk
		LET tracks_a[tracks_a.getLength()].trackno = song_a[x].trackno
		LET tracks_a[tracks_a.getLength()].title = song_a[x].title CLIPPED
		LET tracks_a[tracks_a.getLength()].dur = song_a[x].dur CLIPPED
		LET tracks_a[tracks_a.getLength()].file = song_a[x].file CLIPPED
		LET tracks_a[tracks_a.getLength()].play_count = song_a[x].play_count
		LET tracks_a[tracks_a.getLength()].rating = song_a[x].rating
	END FOR
	CALL xml_r.writeXML("music.xml")
	CALL g2_aui.g2_progBar(3, 0, "")
	CALL buildTree()

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION sortsongs(s)
	DEFINE s t_song
	DEFINE x INTEGER

	LET s.sortby = downshift(s.genre || "-" || s.artist)
	FOR x = 1 TO song_a.getLength()
		IF song_a[x].sortby > s.sortby THEN
			--DISPLAY x,":",song_a[x].sortBy,":",s.sortBy
			CALL song_a.insertElement(x)
			EXIT FOR
		END IF
	END FOR
	LET song_a[x].* = s.*

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION buildTree()
	DEFINE x, y, g, a, t_cnt, album_cnt INTEGER
	DEFINE prev_art STRING

	CALL g2_aui.g2_progBar(1, genre_a.getLength(), "Processing XML - Phase 3 of 3")

	CALL tree_a.clear()
{	DISPLAY CURRENT,": Genre:"||genre_a.getLength()||
					" Artists:"||artist_a.getLength()||
					" Albums:"||album_a.getLength()||
					" Tracks:"||tracks_a.getLength()}
	DISPLAY CURRENT, ": Building Tree ..."
	LET t_cnt = 1
	FOR x = 1 TO genre_a.getLength()
		LET tree_a[t_cnt].id = (genre_a[x].genre_key USING "&&&&&")
		LET g = t_cnt
		LET genre_a[x].artist_cnt = 0
		LET t_cnt = t_cnt + 1
		LET prev_art = "."
		CALL g2_aui.g2_progBar(2, x, "")
		FOR y = 1 TO album_a.getLength()
			IF album_a[y].genre = genre_a[x].genre THEN
				IF album_a[y].artist != prev_art THEN
					LET genre_a[x].artist_cnt = genre_a[x].artist_cnt + 1
					LET tree_a[t_cnt].img = "user"
					LET tree_a[t_cnt].pid = (genre_a[x].genre_key USING "&&&&&")
					LET tree_a[t_cnt].id =
							(genre_a[x].genre_key USING "&&&&&") || "-" || (album_a[y].artist_key USING "&&&&&")
					LET a = t_cnt
					LET t_cnt = t_cnt + 1
					LET prev_art = album_a[y].artist
					LET album_cnt = 0
				END IF
				LET album_cnt = album_cnt + 1
				LET tree_a[t_cnt].img = "cd16"
				LET tree_a[t_cnt].name = album_a[y].album
				LET tree_a[t_cnt].year = album_a[y].year
				LET tree_a[t_cnt].artist_name = album_a[y].artist
				LET tree_a[t_cnt].pid =
						(genre_a[x].genre_key USING "&&&&&") || "-" || (album_a[y].artist_key USING "&&&&&")
				LET tree_a[t_cnt].id =
						(genre_a[x].genre_key USING "&&&&&")
								|| "-"
								|| (album_a[y].artist_key USING "&&&&&")
								|| "-"
								|| (album_a[y].album_key USING "&&&&&")
				LET t_cnt = t_cnt + 1
				LET tree_a[a].name = album_a[y].artist || " (" || album_cnt || ")"
				LET tree_a[a].artist_name = album_a[y].artist
			END IF
		END FOR
		LET tree_a[g].name = genre_a[x].genre || " (" || genre_a[x].artist_cnt || ")"
	END FOR

{	FOR x = 1 TO tree_a.getLength()
		DISPLAY tree_a[ x ].id, " PID:", tree_a[ x ].pid, " NAME:",tree_a[ x ].name
	END FOR}
	CALL g2_aui.g2_progBar(3, 0, "")
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION showBranch(g, ar, al, tf)
	DEFINE g, ar, al INTEGER
	DEFINE tf BOOLEAN
	DEFINE y, x INTEGER
	DEFINE id1, id2, id3 CHAR(5)
	DEFINE d ui.Dialog

	LET d = ui.dialog.getCurrent()

	LET id1 = (g USING "&&&&&")
	LET id2 = (ar USING "&&&&&")
	LET id3 = (al USING "&&&&&")
	--DISPLAY "Id:",id1,"-",id2,"-",id3

	IF g = 0 AND al = 0 AND ar = 0 THEN
		FOR y = 1 TO tree_a.getLength()
			LET tree_a[y].expanded = tf
		END FOR
		RETURN
	END IF

	IF al > 0 THEN
		FOR y = 1 TO tree_a.getLength() -- Expand branches for albums found.
			IF tree_a[y].id.subString(13, 17) = id3 THEN
				LET tree_a[y].expanded = tf
				--			CALL d.setSelectionRange("tree",y,y,TRUE)
				--ELSE
				--LET tree_a[y].expanded = NOT tf
			END IF
		END FOR
	END IF
	IF ar > 0 THEN
		FOR y = 1 TO tree_a.getLength() -- Expand branches for artist found.
			IF tree_a[y].id.subString(7, 11) = id2 THEN
				LET tree_a[y].expanded = tf
				--			CALL d.setSelectionRange("tree",y,y,TRUE)
				--ELSE
				--LET tree_a[y].expanded = NOT tf
			END IF
		END FOR
	END IF

-- Fixes genre according to any expanded children
	FOR y = 1 TO tree_a.getLength() -- Expand/Collapse branches for genre found.
		IF tree_a[y].id.getLength() = 5 THEN
			LET tree_a[y].expanded = FALSE
			FOR x = y + 1 TO tree_a.getLength()
				IF tree_a[x].id.subString(1, 5) != tree_a[y].id.subString(1, 5) THEN
					EXIT FOR
				END IF
				IF tree_a[x].expanded THEN -- if child expanded.
					LET tree_a[y].expanded = TRUE -- Expand parent
					EXIT FOR
				END IF
			END FOR
		END IF
	END FOR

-- Now see if they wanted to expand any specific genre.
	IF g > 0 THEN
		FOR y = 1 TO tree_a.getLength() -- Expand branches for genre found.
			IF tree_a[y].id.subString(1, 5) = id1 AND tree_a[y].id.getLength() = 5 THEN
				LET tree_a[y].expanded = tf
				--			CALL d.setSelectionRange("tree",y,y,TRUE)
			ELSE
				LET tree_a[y].expanded = NOT tf
			END IF
		END FOR
	END IF
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION dispRowDetails(g, art, alb)
	DEFINE g, art, alb, x INTEGER
	DEFINE album_name STRING
	DEFINE id STRING
	DEFINE d ui.dialog

	IF alb > 0 THEN
		LET album_name = album_a[alb].album
	END IF
	LET id = (g USING "&&&&&") || "-" || (art USING "&&&&&") || "-" || (alb USING "&&&&&")

	DISPLAY CURRENT, ": Track Row G:", g, " Art:", art, " Alb:", alb, " ID:", id

	IF g IS NOT NULL THEN
		DISPLAY genre_a[g].genre TO genre
		LET g = 0
	END IF
	DISPLAY artist_a[art].artist TO artist
	DISPLAY album_name TO album
	DISPLAY sel_tracks_a.getLength() TO nooftracks

	IF id IS NOT NULL THEN
		FOR x = 1 TO tree_a.getLength()
			IF tree_a[x].id = id THEN
				LET d = ui.dialog.getCurrent()
				CALL d.setCurrentRow("tree", x)
				DISPLAY "Found Tree node! : ", x
				EXIT FOR
			END IF
		END FOR
	END IF

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION loadTracks(id)
	DEFINE id STRING
	DEFINE g, art, alb, x, y INTEGER
	DEFINE tracks_tmp DYNAMIC ARRAY OF t_tracks

-- 12345678901234567
-- 00000-00000-00000

	LET g = id.subString(1, 5)
	LET art = id.subString(7, 11)
	LET alb = id.subString(13, 17)

	IF art IS NULL THEN
		RETURN
	END IF
	IF alb IS NULL THEN
		LET alb = 0
	END IF
	DISPLAY CURRENT, ": Loading Tracks - ID:", id, " G:", g, " Art:", art, " Alb:", alb

	CALL sel_tracks_a.clear()
	IF art > 0 THEN
		FOR x = 1 TO tracks_a.getLength()
			IF tracks_a[x].artist_key = art THEN
				IF alb = 0 OR tracks_a[x].album_key = alb THEN
					LET tracks_tmp[tracks_tmp.getLength() + 1].genre_key = tracks_a[x].genre_key
					LET tracks_tmp[tracks_tmp.getLength()].artist_key = tracks_a[x].artist_key
					LET tracks_tmp[tracks_tmp.getLength()].album_key = tracks_a[x].album_key
					LET tracks_tmp[tracks_tmp.getLength()].title = tracks_a[x].title
					LET tracks_tmp[tracks_tmp.getLength()].trackno = tracks_a[x].trackno
					LET tracks_tmp[tracks_tmp.getLength()].image = "note"
					LET tracks_tmp[tracks_tmp.getLength()].dur = tracks_a[x].dur
					LET tracks_tmp[tracks_tmp.getLength()].file = tracks_a[x].file
					LET tracks_tmp[tracks_tmp.getLength()].play_count = tracks_a[x].play_count
					LET tracks_tmp[tracks_tmp.getLength()].rating = tracks_a[x].rating
					IF tracks_a[x].rating IS NULL THEN
						LET tracks_a[x].rating = 0
					END IF
					LET tracks_tmp[tracks_tmp.getLength()].rating = tracks_a[x].rating USING "<&&"
				END IF
			END IF
		END FOR
	END IF
-- Now sort track list my trackNo.
	FOR y = 0 TO 60
		FOR x = 1 TO tracks_tmp.getLength()
			IF y = tracks_tmp[x].trackno THEN
				LET sel_tracks_a[sel_tracks_a.getLength() + 1].* = tracks_tmp[x].*
			END IF
		END FOR
	END FOR

	CALL dispRowDetails(g, art, alb)

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION setSelTrack(x)
	DEFINE x INTEGER

	LET sel_tracks_a[sel_tracks_a.getLength() + 1].genre_key = tracks_a[x].genre_key
	LET sel_tracks_a[sel_tracks_a.getLength()].artist_key = tracks_a[x].artist_key
	LET sel_tracks_a[sel_tracks_a.getLength()].album_key = tracks_a[x].album_key
	LET sel_tracks_a[sel_tracks_a.getLength()].title = tracks_a[x].title
	LET sel_tracks_a[sel_tracks_a.getLength()].trackno = tracks_a[x].trackno
	LET sel_tracks_a[sel_tracks_a.getLength()].image = "note"
	LET sel_tracks_a[sel_tracks_a.getLength()].dur = tracks_a[x].dur
	LET sel_tracks_a[sel_tracks_a.getLength()].file = tracks_a[x].file
	LET sel_tracks_a[sel_tracks_a.getLength()].play_count = tracks_a[x].play_count
	IF tracks_a[x].rating IS NULL THEN
		LET tracks_a[x].rating = 0
	END IF
	LET sel_tracks_a[sel_tracks_a.getLength()].rating = tracks_a[x].rating USING "&&"

END FUNCTION
------------------------------------------------------------------------------------
--
FUNCTION getAlbumArtURL(l_alb STRING)
	DEFINE l_album_id, l_img STRING
	CALL g2_lib.g2_message("Getting album artwork...")
	LET m_album_art_cover = NULL
	LET m_musicbrainz_url = NULL
	DISPLAY "noimage" TO album_art

	IF m_album_art_artist.getLength() = 0 THEN
		RETURN "noimage"
	END IF

	LET l_album_id = getAlbumID(l_alb)
	IF l_album_id IS NULL THEN
		RETURN "noimage"
	END IF
	LET m_mb = m_mb.append("\nAlbum:" || l_alb || " (" || l_album_id || ")")

	LET l_img = getArtworkURL(l_album_id)
	IF l_img IS NULL THEN
		RETURN "noimage"
	END IF

	CALL g2_lib.g2_message("Album art found: " || l_img)
	RETURN l_img
END FUNCTION
--------------------------------------------------------------------------------
-- GET /release/76df3287-6cda-33eb-8e9a-044b5e15ffdd HTTP/1.1
-- Host: coverartarchive.org
FUNCTION getArtworkURL(l_album_id STRING)
	DEFINE l_url, l_line STRING
	DEFINE json_rec RECORD
		images DYNAMIC ARRAY OF RECORD
			image STRING,
			thumbnails RECORD
				large STRING,
				small STRING
			END RECORD
		END RECORD
	END RECORD
	DEFINE l_img STRING
	DEFINE c base.channel

	LET l_url = 'http://coverartarchive.org/release/' || l_album_id.trim()
	CALL g2_lib.g2_message("Getting Album artwork from:" || NVL(l_url, "NULL"))

	-- redirection that happens causes a bug in gws library
	-- failing back to wget
	IF os.path.pathSeparator() = ":" THEN -- Linux / Mac
		LET l_line = "unset LD_LIBRARY_PATH && wget -o tmp.out -O - " || l_url
	ELSE -- DOS
		LET l_line = "wget.exe -o tmp.out -O - " || l_url
	END IF
	DISPLAY "Opening Pipe for: ", l_line
	LET c = base.channel.create()
	CALL c.openPipe(l_line, "r")
	LET l_line = c.readLine()
	CALL c.close()

--  LET l_line = getRestRequest( l_url  )

	IF l_line IS NULL THEN
		RUN "cat tmp.out"
		CALL g2_lib.g2_message("Failed to get album art!")
		RETURN NULL
	END IF

	TRY
		CALL util.JSON.parse(l_line, json_rec)
	CATCH
		DISPLAY "Line:", l_line
		ERROR "JSON Error:" || STATUS || ":" || err_get(STATUS)
		RETURN NULL
	END TRY
	LET l_img = json_rec.images[1].image
	LET m_album_art_cover = l_img
	IF json_rec.images[1].thumbnails.small IS NOT NULL THEN
		LET l_img = json_rec.images[1].thumbnails.small
	END IF
	DISPLAY "Img: ", l_img
	RETURN l_img.trim()
END FUNCTION
--------------------------------------------------------------------------------
-- http://musicbrainz.org/ws/2/release/?query=%22blackbirds%22%20AND%20arid:ca311a64-0a30-4fdb-ad0c-02444b8b0b8b&fmt=json;
{
  "count": 2,
  "offset": 0,
  "releases": [
    {
      "id": "b00b75e9-ccc2-4e7e-b880-92990eed6204",
      "score": "100",
      "count": 1,
      "title": "Blackbirds",
}
FUNCTION getAlbumID(l_alb STRING)
	DEFINE l_url, l_line, l_id, l_title STRING
	DEFINE l_result RECORD
		count SMALLINT,
		releases DYNAMIC ARRAY OF RECORD
			id STRING,
			score SMALLINT,
			title STRING
		END RECORD
	END RECORD
	DEFINE l_album_art_artist_id STRING
	DEFINE x, y, l_score SMALLINT

	FOR x = 1 TO m_album_art_artist.getLength()
		LET l_url =
				'http://musicbrainz.org/ws/2/release/?query="'
						|| l_alb
						|| '" AND arid:'
						|| m_album_art_artist[x].id
						|| '&fmt=json'
		LET l_line = getRestRequest(l_url)
		IF l_line IS NULL THEN
			RETURN NULL
		END IF
		TRY
			CALL util.JSON.parse(l_line, l_result)
		CATCH
			ERROR "JSON Error:" || STATUS || ":" || err_get(STATUS)
			RETURN NULL
		END TRY
		IF l_result.count > 0 THEN
			EXIT FOR
		END IF
	END FOR

	DISPLAY "Found ", l_result.count, " Albums ..."
	IF l_result.count = 0 THEN
		DISPLAY "Line:", l_line
		CALL g2_lib.g2_message("Album not found!")
		RETURN NULL
	END IF

	-- replace m_mb with actually artist for this album
	LET l_album_art_artist_id = m_album_art_artist[x].id
	LET m_mb = "Artist:", m_artist, " (", l_album_art_artist_id, ")"

-- delete the album_art_artist entries that are for this album
	FOR y = 1 TO m_album_art_artist.getLength()
		IF y != x THEN
			CALL m_album_art_artist.deleteElement(y)
		END IF
	END FOR

	LET l_score = 0
	FOR x = 1 TO l_result.count
		IF l_result.releases[x].score > l_score THEN
			LET l_score = l_result.releases[x].score
			LET l_id = l_result.releases[x].id
			LET l_title = l_result.releases[x].title

			IF l_score = 100 THEN
				EXIT FOR
			END IF
		END IF
		DISPLAY "Score: ", l_result.releases[x].score, ":", l_result.releases[x].title
	END FOR
	DISPLAY "Album: ", NVL(l_id, "NULL"), " : ", l_title
	LET m_musicbrainz_url = "https://musicbrainz.org/release/" || l_id
	CALL g2_lib.g2_message(SFMT("Album %1 Found, id:%2", l_title, l_id))
	RETURN l_id
END FUNCTION
--------------------------------------------------------------------------------
-- https://musicbrainz.org/ws/2/artist/?query=%22gretchen%20peters%22&fmt=json;
-- result:
{
  "created": "2018-02-13T09:43:27.157Z",
  "count": 1,
  "offset": 0,
  "artists": [
    {
      "id": "ca311a64-0a30-4fdb-ad0c-02444b8b0b8b",
			"score": "100",
}
FUNCTION getArtistID(l_art STRING)
	DEFINE l_url, l_line, l_id, l_name STRING
	DEFINE l_artist RECORD
		count SMALLINT,
		artists DYNAMIC ARRAY OF RECORD
			id STRING,
			score SMALLINT,
			name STRING
		END RECORD
	END RECORD
	DEFINE x SMALLINT

	LET l_url = 'http://musicbrainz.org/ws/2/artist/?query="' || l_art.trim() || '"&fmt=json'
	LET l_line = getRestRequest(l_url)
	IF l_line IS NULL THEN
		RETURN NULL
	END IF
	TRY
		CALL util.JSON.parse(l_line, l_artist)
	CATCH
		ERROR "JSON Error:" || STATUS || ":" || err_get(STATUS)
		RETURN NULL
	END TRY
	IF l_artist.count = 0 THEN
		CALL g2_lib.g2_message("Artist not found!")
		RETURN NULL
	END IF
	CALL m_album_art_artist.clear()

	FOR x = 1 TO l_artist.count
		IF l_artist.artists[x].score > 80 THEN
			LET m_album_art_artist[m_album_art_artist.getLength() + 1].score = l_artist.artists[x].score
			LET m_album_art_artist[m_album_art_artist.getLength()].id = l_artist.artists[x].id
			LET m_album_art_artist[m_album_art_artist.getLength()].name = l_artist.artists[x].name
		END IF
	END FOR
	CALL m_album_art_artist.sort("score", TRUE)
	DISPLAY "Found ", m_album_art_artist.getLength(), " Artists:"
	FOR x = 1 TO m_album_art_artist.getLength()
		DISPLAY m_album_art_artist[x].score,
				" : ",
				m_album_art_artist[x].id,
				" : ",
				m_album_art_artist[x].name
	END FOR
	LET l_id = m_album_art_artist[1].id
	LET l_name = m_album_art_artist[1].name
	LET m_musicbrainz_url = "https://musicbrainz.org/artist/" || l_id
	DISPLAY "Artist: ", NVL(l_id, "NULL"), " : ", l_name
	CALL g2_lib.g2_message(SFMT("Artist %1 Found, id:%2", l_name, l_id))
	RETURN l_id
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION getRestRequest(l_url STRING)
	DEFINE l_err BOOLEAN
	DEFINE l_req com.HttpRequest
	DEFINE l_resp com.HttpResponse
	DEFINE l_line STRING

	DISPLAY CURRENT, ": URL=", l_url
	TRY
		LET l_req = com.HttpRequest.Create(l_url)
		CALL l_req.setMethod("GET")
		CALL l_req.setVersion("1.1")
--		CALL l_req.setCharset("UTF-8")
		CALL l_req.setHeader("Content-Type", "application/json")
		CALL l_req.setHeader("Accept", "application/json")
		CALL l_req.setHeader("Expect", "100-continue") --??
		CALL l_req.doRequest()
		LET l_resp = l_req.getResponse()
	CATCH
		LET m_getAlbumArt = FALSE
		RETURN NULL
	END TRY

	DISPLAY CURRENT, ": Reading result ..."
	LET l_err = TRUE
	TRY
		IF l_resp.getStatusCode() = 200 THEN
			LET l_line = l_resp.getTextResponse()
			LET l_err = FALSE
		ELSE
			LET l_line = SFMT("WARN:%1-%2", l_resp.getStatusCode(), l_resp.getStatusDescription())
		END IF
	CATCH
		LET l_line = SFMT("ERR:%1-%2", STATUS, SQLCA.SQLERRM)
	END TRY

	DISPLAY CURRENT, ": Line:", l_line
	IF l_err THEN
		RETURN NULL
	END IF

	RETURN l_line
END FUNCTION
--------------------------------------------------------------------------------
--DB Functions.
--------------------------------------------------------------------------------
FUNCTION db_mk_tab()

	DISPLAY "Drop Tables ..."
	TRY
		DROP TABLE ipod_genre
	CATCH
	END TRY
	TRY
		DROP TABLE ipod_artists
	CATCH
	END TRY
	TRY
		DROP TABLE ipod_albums
	CATCH
	END TRY
	TRY
		DROP TABLE ipod_tracks
	CATCH
	END TRY

	DISPLAY "Create Table  'ipod_genre'..."
	TRY
		CREATE TABLE ipod_genre(genre_key SERIAL, genre VARCHAR(40))
	CATCH
		CALL g2_lib.g2_errPopup(% "failed to create 'ipod_genre'\n" || SQLERRMESSAGE)
		EXIT PROGRAM
	END TRY
	DISPLAY "Created Table 'ipod_genre'"

	DISPLAY "Create Table  'ipod_artists'..."
	TRY
		CREATE TABLE ipod_artists(artist_key SERIAL, artist VARCHAR(50))
	CATCH
		CALL g2_lib.g2_errPopup(% "failed to create 'ipod_artists'\n" || SQLERRMESSAGE)
		EXIT PROGRAM
	END TRY
	DISPLAY "Create Table 'ipod_artists'"

	DISPLAY "Create Table  'ipod_albums'..."
	TRY
		CREATE TABLE ipod_albums(
				album_key SERIAL, genre_key INTEGER, artist_key INTEGER, album VARCHAR(50), year CHAR(4))
	CATCH
		CALL g2_lib.g2_errPopup(% "failed to create 'ipod_albums'\n" || SQLERRMESSAGE)
		EXIT PROGRAM
	END TRY
	DISPLAY "Create Table 'ipod_albums'"

	DISPLAY "Create Table  'ipod_tracks'..."
	TRY
		CREATE TABLE ipod_tracks(
				track_key SERIAL,
				album_key INTEGER,
				track_no SMALLINT,
				track VARCHAR(60),
				dur VARCHAR(10),
				file VARCHAR(100),
				play_count SMALLINT,
				rating SMALLINT)
	CATCH
		CALL g2_lib.g2_errPopup(% "failed to create 'ipod_tracks'\n" || SQLERRMESSAGE)
		EXIT PROGRAM
	END TRY
	DISPLAY "Create Table 'ipod_tracks'"

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION db_load_tab()
	DEFINE x, y, ak INTEGER
	DEFINE vc VARCHAR(60)

	DISPLAY CURRENT, ":Loading " || genre_a.getLength() || " Genre ..."
	MESSAGE "Loading " || genre_a.getLength() || " Genre ..."
	CALL ui.interface.refresh()
	BEGIN WORK
	FOR x = 1 TO genre_a.getLength()
		LET vc = genre_a[x].genre
		INSERT INTO ipod_genre VALUES(0, vc)
		LET genre_a[x].genre_key = SQLCA.sqlerrd[2]
		--DISPLAY "Genre:",genre_a[x].genre,":",genre_a[x].genre_key
	END FOR
	COMMIT WORK

	DISPLAY CURRENT, ":Loading " || artist_a.getLength() || " Artists ..."
	MESSAGE "Loading " || artist_a.getLength() || " Artists ..."
	CALL ui.interface.refresh()
	DECLARE art_put_cur CURSOR FOR INSERT INTO ipod_artists VALUES(0, ?)
	BEGIN WORK
	OPEN art_put_cur
	FOR x = 1 TO artist_a.getLength()
		LET vc = artist_a[x].artist
-- NOTE: can't use PUT because it doesn't set SQLCA with last serial !!
		EXECUTE art_put_cur USING vc
		LET artist_a[x].artist_key = SQLCA.sqlerrd[2]
		--DISPLAY "Artist:",artist_a[x].artist,":",artist_a[x].artist_key
	END FOR
	CLOSE art_put_cur
	COMMIT WORK

	DISPLAY CURRENT, ":Loading " || album_a.getLength() || " Albums ..."
	MESSAGE "Loading " || album_a.getLength() || " Albums ..."
	CALL ui.interface.refresh()
	DECLARE alb_put_cur CURSOR FOR INSERT INTO ipod_albums VALUES(0, ?, ?, ?, ?)
	BEGIN WORK
	OPEN alb_put_cur
	FOR x = 1 TO album_a.getLength()
		LET vc = album_a[x].album
		FOR y = 1 TO genre_a.getLength()
			IF album_a[x].genre = genre_a[y].genre THEN
				LET album_a[x].genre_key = genre_a[y].genre_key
				EXIT FOR
			END IF
		END FOR
		FOR y = 1 TO artist_a.getLength()
			IF artist_a[y].artist IS NULL THEN
				CONTINUE FOR
			END IF
			IF album_a[x].artist = artist_a[y].artist THEN
				LET album_a[x].artist_key = artist_a[y].artist_key
				EXIT FOR
			END IF
		END FOR
		EXECUTE alb_put_cur USING album_a[x].genre_key, album_a[x].artist_key, vc, album_a[x].year
		LET album_a[x].album_key = SQLCA.sqlerrd[2]
		--DISPLAY "Album:",album_a[x].album,":",album_a[x].album_key, " Artist:",album_a[x].artist_key," Genre:",album_a[x].genre_key
	END FOR
	CLOSE alb_put_cur
	COMMIT WORK

	DISPLAY CURRENT, ":Loading " || song_a.getLength() || " Tracks ..."
	MESSAGE "Loading " || song_a.getLength() || " Tracks ..."
	CALL ui.interface.refresh()
	DECLARE sng_put_cur CURSOR FOR INSERT INTO ipod_tracks VALUES(0, ?, ?, ?, ?, ?, ?, ?)
	BEGIN WORK
	OPEN sng_put_cur
	FOR x = 1 TO song_a.getLength()
		LET vc = song_a[x].title
		FOR y = 1 TO album_a.getLength()
			IF song_a[x].artist = album_a[y].artist AND song_a[x].album = album_a[y].album THEN
				LET ak = album_a[y].album_key
			END IF
		END FOR
		PUT sng_put_cur FROM ak,
				song_a[x].trackno,
				vc,
				song_a[x].dur,
				song_a[x].file,
				song_a[x].play_count,
				song_a[x].rating
	END FOR
	CLOSE sng_put_cur
	COMMIT WORK

	SELECT COUNT(*) INTO x FROM ipod_tracks
	DISPLAY CURRENT, ":Loaded " || x || " Songs..."

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION db_read()
	DEFINE vc, vc2, vc3 VARCHAR(60)
	DEFINE yr CHAR(4)
	DEFINE gk, ark, alk INTEGER
	DEFINE l_trk RECORD
		track_key INTEGER,
		album_key INTEGER,
		track_no SMALLINT,
		track VARCHAR(60),
		dur VARCHAR(10),
		file VARCHAR(100),
		play_count SMALLINT,
		rating SMALLINT
	END RECORD

	CALL genre_a.clear()
	CALL album_a.clear()
	CALL artist_a.clear()
	CALL tracks_a.clear()

	DISPLAY CURRENT, ": Populating the arrays from database ..."
	DECLARE g_cur CURSOR FOR SELECT genre, genre_key FROM ipod_genre ORDER BY genre
	DECLARE a_cur CURSOR FOR
			SELECT al.album, al.album_key, ar.artist, ar.artist_key, al.year
					FROM ipod_albums al, ipod_artists ar
					WHERE al.genre_key = gk AND al.artist_key = ar.artist_key
					ORDER BY artist, album

	FOREACH g_cur INTO vc, gk
		LET genre_a[gk].genre = vc
		LET genre_a[gk].genre_key = gk
		FOREACH a_cur INTO vc2, alk, vc3, ark, yr
			--DISPLAY vc,":",vc2,":",vc3
			LET album_a[alk].genre = vc
			LET album_a[alk].genre_key = gk
			LET album_a[alk].album = vc2
			LET album_a[alk].album_key = alk
			LET album_a[alk].artist = vc3
			LET album_a[alk].artist_key = ark
			LET album_a[alk].year = yr
			LET artist_a[ark].artist = vc3
			LET artist_a[ark].artist_key = ark
			--DISPLAY album_a[ alk ].*
		END FOREACH
	END FOREACH

	DECLARE t_cur CURSOR FOR
			SELECT ipod_tracks.*, artist_key
					FROM ipod_tracks t, ipod_albums a
					WHERE t.album_key = a.album_key
					ORDER BY t.album_key, track_no
	FOREACH t_cur INTO l_trk.*, ark
		LET tracks_a[tracks_a.getLength() + 1].artist_key = ark
		LET tracks_a[tracks_a.getLength()].album_key = l_trk.album_key
		LET tracks_a[tracks_a.getLength()].trackno = l_trk.track_no
		LET tracks_a[tracks_a.getLength()].title = l_trk.track
		LET tracks_a[tracks_a.getLength()].dur = l_trk.dur
		LET tracks_a[tracks_a.getLength()].file = l_trk.file
		LET tracks_a[tracks_a.getLength()].play_count = l_trk.play_count
		LET tracks_a[tracks_a.getLength()].rating = l_trk.rating
		LET t_min = t_min + tracks_a[tracks_a.getLength()].dur[1, 2]
		LET t_sec = t_sec + tracks_a[tracks_a.getLength()].dur[4, 5]
	END FOREACH

	CALL buildTree()

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION show_big_cover(l_img STRING)
	DEFINE l_ret SMALLINT
	OPEN WINDOW big_cover WITH FORM "ipod_big_cover"
	DISPLAY BY NAME l_img
	MENU
		ON ACTION openbrowser
			CALL ui.Interface.frontCall("standard","launchURL", l_img, l_ret)
		ON ACTION close
			EXIT MENU
	END MENU
	CLOSE WINDOW big_cover
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION erro()
	DISPLAY "----------------------------------------------"
	IF STATUS != 0 THEN
		DISPLAY STATUS, ":", SQLERRMESSAGE
	END IF
	DISPLAY base.application.getstacktrace()
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION tidyup()
-- Oh dear, a timeout has been reach, must close nicely
	DISPLAY CURRENT, ": Tidyup"
END FUNCTION
--------------------------------------------------------------------------------
