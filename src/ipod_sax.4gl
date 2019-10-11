
IMPORT FGL g2_aui

DEFINE attr_name STRING

CONSTANT PMAX = 10000
DEFINE xml_d om.domDocument

DEFINE song_r om.domNode
DEFINE song_n om.domNode
DEFINE typ STRING
DEFINE ignore_rest SMALLINT
DEFINE p_cnt SMALLINT

FUNCTION startDocument()

  DISPLAY CURRENT, ": SaxHandler - StartDocument"

  LET xml_d = om.domDocument.create("Library")
  LET song_r = xml_d.createElement("SongList")

  LET ignore_rest = FALSE
  LET p_cnt = 0
  CALL g2_aui.g2_progBar(1, PMAX, "Load XML data,  please wait ...")
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION processingInstruction(name, data)
  DEFINE name, data STRING

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION startElement(name, attr)
  DEFINE name STRING
  DEFINE attr om.SaxAttributes

  IF ignore_rest THEN
    RETURN
  END IF

  LET p_cnt = p_cnt + 1
  IF NOT (p_cnt MOD 100) THEN
    CALL g2_aui.g2_progBar(2, p_cnt, "")
  END IF
  IF p_cnt = PMAX THEN
    LET p_cnt = 0
  END IF

  IF name = "array" THEN
    LET typ = "array"
    LET song_n = NULL
    LET ignore_rest = TRUE
  END IF
  IF name = "dict" THEN
    LET song_n = song_r.createChild("Song")
  END IF
  IF name = "key" THEN
    LET typ = "key"
  END IF
  IF name = "string" THEN
    LET typ = "string"
  END IF
  IF name = "integer" THEN
    LET typ = "integer"
  END IF

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION endElement(name)
  DEFINE name STRING

--	DISPLAY "endElement"

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION endDocument()

--	CALL song_r.writeXML("songs.xml")
  CALL set_xml_n(song_r)
  DISPLAY CURRENT, ": SaxHandler - EndDocument"
  CALL g2_aui.g2_progBar(3, 0, "")

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION characters(chars)
  DEFINE chars STRING
  DEFINE attr CHAR(40)
  DEFINE x SMALLINT
  DEFINE c om.DomNode

  IF ignore_rest THEN
    RETURN
  END IF
  IF song_n IS NULL THEN
    RETURN
  END IF

  IF typ = "key" THEN
    LET attr = chars.toLowerCase()
    FOR x = 1 TO length(attr)
      IF attr[x] = " " THEN
        LET attr[x] = "_"
      END IF
    END FOR
    LET attr_name = attr CLIPPED
  ELSE
    IF attr_name.trim() = "location" THEN
      LET x = chars.getIndexOF(":", 10)
      LET chars = fix_tokens(chars.subString(x - 1, chars.getLength()))

      LET c = xml_d.createChars(chars.trim())
      CALL song_n.appendChild(c)
    ELSE
      CALL song_n.setAttribute(attr_name, chars.trim())
    END IF
  END IF

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION fix_tokens(str)
  DEFINE str, ret STRING
  DEFINE x SMALLINT
  DEFINE chr CHAR(1)

  FOR x = 1 TO str.getLength()
    LET chr = str.getCharAt(x)
    CASE chr
      WHEN "&"
        IF str.subString(x, x + 4) = "&amp;" OR str.subString(x, x + 4) = "&#38;" THEN
          LET chr = "&"
          LET x = x + 4
        ELSE
--				DISPLAY "Unknown token:&:",x,":",str.subString(x,x+4),":"
        END IF
      WHEN "%"
        IF str.subString(x, x + 2) = "%20" THEN
          LET chr = " "
          LET x = x + 2
        ELSE
--					DISPLAY "Unknown token:%:",x,":",str.subString(x,x+4),":"
        END IF
    END CASE
    LET ret = ret.append(chr)
  END FOR
  RETURN ret
END FUNCTION
--------------------------------------------------------------------------------
