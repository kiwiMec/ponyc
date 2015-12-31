use "ponytest"

actor Main is TestList
  new create(env: Env) => PonyTest(env, this)
  new make() => None

  fun tag tests(test: PonyTest) =>
    test(_TestFnMatchCase)
    test(_TestFilter)
    test(_TestMkdtemp)
    test(_TestWalk)
    test(_TestGlob)
    test(_TestIGlob)

    test(_TestFnMatch("abc", "abc", true))
    test(_TestFnMatch("abc", "a.c", false))

    // Make sure regular expression special characters don't screw things up.
    test(_TestFnMatch("a[].\\()c", "a[].\\()c", true))
    test(_TestFnMatch("a[].\\()d", "a[].\\()c", false))

    // Globs don't allow wild card escaping (it would mess up windows paths).
    test(_TestFnMatch("a*d", "a\\*c", false))
    test(_TestFnMatch("a\\bdc", "a\\*c", true))
    test(_TestFnMatch("a?c", "a\\?c", false))
    test(_TestFnMatch("a\\bc", "a\\?c", true))

    test(_TestFnMatch("abc", "a?c", true))
    test(_TestFnMatch("abbc", "a?c", false))
    test(_TestFnMatch("a/c", "a?c", false))

    test(_TestFnMatch("ac", "a*c", true))
    test(_TestFnMatch("abc", "a*c", true))
    test(_TestFnMatch("abbc", "a*c", true))
    test(_TestFnMatch("a/c", "a*c", false))
    test(_TestFnMatch("abc/def", "a*/*f", true))
    test(_TestFnMatch("a/ccc/d/f", "a/*/?/f", true))

    test(_TestFnMatch("ac", "a**c", true))
    test(_TestFnMatch("abc", "a**c", true))
    test(_TestFnMatch("abbc", "a**c", true))
    test(_TestFnMatch("a/c", "a**c", true))
    test(_TestFnMatch("ab/bc", "a**c", true))
    test(_TestFnMatch("a/b/c", "a**c", true))

    test(_TestFnMatch("a1c", "a[12]c", true))
    test(_TestFnMatch("a2c", "a[12]c", true))
    test(_TestFnMatch("a3c", "a[12]c", false))
    test(_TestFnMatch("a3c", "a[!12]c", true))
    test(_TestFnMatch("a2c", "a[!12]c", false))
    test(_TestFnMatch("a1c", "a[!12]c", false))
    test(_TestFnMatch("a11c", "a[12]c", false))
    test(_TestFnMatch("a12c", "a[12]c", false))

primitive _FileHelper
  fun make_files(h: TestHelper, files: Array[String]): FilePath? =>
    let top = Directory(FilePath.mkdtemp(h.env.root, "tmp._FileHelper.XXXXXX"))
    for f in files.values() do
      try
        let dir_head = Path.split(f)
        let fp = FilePath(top.path, dir_head._1)
        fp.mkdir()
        if dir_head._2 != "" then
          Directory(fp).create_file(dir_head._2)
        end
      else
        h.assert_failed("Failed to create file: " + f)
        h.expect_true(top.path.remove())
        error
      end
    end
    top.path


class iso _TestMkdtemp is UnitTest
  fun name(): String => "files/FilePath.mkdtemp"
  fun apply(h: TestHelper): TestResult? =>
    h.expect_error(lambda()(h = h)? => FilePath.mkdtemp(h.env.root, "tmp") end,
        "FilePath.mkdtemp should fail when path doesn't have a XXXXXX suffix")

    let tmp = FilePath.mkdtemp(h.env.root, "tmp.TestMkdtemp.XXXXXX")
    try
      h.expect_true(FileInfo(tmp).directory)
    then
      h.expect_true(tmp.remove())
    end
    true

class iso _TestWalk is UnitTest
  fun name(): String => "files/FilePath.walk"
  fun apply(h: TestHelper): TestResult? =>
    let top = _FileHelper.make_files(h, ["a/1", "a/2", "b", "c/3", "c/4", "d/5", "d/6"])
    try
      top.walk(
          lambda(dir: FilePath, entries: Array[String] ref)
                (p = top.path, h = h) =>
        if dir.path == p then
          h.expect_array_eq[String](entries, ["a", "b", "c", "d"])
          entries.remove(2, 1)
        elseif dir.path.at("a", -1) then
          h.expect_array_eq[String](entries, ["1", "2"])
        elseif dir.path.at("d", -1) then
          h.expect_array_eq[String](entries, ["5", "6"])
        else
          h.assert_failed("Unexpected dir: " + dir.path)
        end
      end)
    then
    h.expect_true(top.remove())
    end
    true

class iso _TestFnMatchCase is UnitTest
  fun name(): String => "files/Glob.fnmatchcase"

  fun apply(h: TestHelper): TestResult =>
    h.expect_true(Glob.fnmatchcase("aBc", "aBc"))
    h.expect_false(Glob.fnmatchcase("aBc", "abc"))
    true

class iso _TestFnMatch is UnitTest
  let _glob: String
  let _path: String
  let _matches: Bool

  new iso create(glob: String, path: String, matches: Bool) =>
    _glob = glob
    _path = path
    _matches = matches

  fun name(): String =>
    "files/" + (if _matches then "" else "!" end) +
      "Glob.fnmatch(" + _glob + ", " + _path + ")"

  fun apply(h: TestHelper): TestResult =>
    _matches == Glob.fnmatch(_glob, _path)

class iso _TestFilter is UnitTest
  fun name(): String => "files/Glob.filter"

  fun apply(h: TestHelper): TestResult? =>
    let m = Glob.filter([ "12/a/Bcd", "12/q/abd", "34/b/Befd"], "*/?/B*d")
    h.assert_eq[USize](2, m.size())

    h.expect_eq[String](m(0)._1, "12/a/Bcd")
    h.expect_array_eq[String](m(0)._2, ["12", "a", "c"])

    h.expect_eq[String](m(1)._1, "34/b/Befd")
    h.expect_array_eq[String](m(1)._2, ["34", "b", "ef"])
    true

class iso _TestGlob is UnitTest
  fun name(): String => "files/FilePath.glob"
  fun _rel(top: FilePath, files: Array[FilePath]): Array[String]? =>
    let res = recover ref Array[String] end
    for fp in files.values() do
      res.push(Path.rel(top.path, fp.path))
    end
    res

  fun apply(h: TestHelper): TestResult? =>
    let top = _FileHelper.make_files(h, ["a/1", "a/2", "b", "c/1", "c/4"])
    try
      h.expect_array_eq[String](_rel(top, Glob.glob(top, "*/1")), ["a/1", "c/1"])
    then
      h.expect_true(top.remove())
    end
    true

class iso _TestIGlob is UnitTest
  fun name(): String => "files/FilePath.iglob"
  fun _rel(top: FilePath, files: Array[FilePath]): Array[String]? =>
    let res = recover ref Array[String] end
    for fp in files.values() do
      res.push(Path.rel(top.path, fp.path))
    end
    res

  fun apply(h: TestHelper): TestResult? =>
    let top = _FileHelper.make_files(h, ["a/1", "a/2", "b", "c/1", "c/4"])
    try
      Glob.iglob(top, "*/1",
          lambda(f: FilePath, matches: Array[String])
                (top = top, h = h) =>
        try
          match matches(0)
          | "a" => h.expect_eq[String](Path.rel(top.path, f.path), "a/1")
          | "b" => h.expect_eq[String](Path.rel(top.path, f.path), "b/1")
          else
            error
          end
        else
            h.assert_failed("Unexpected match: " + f.path)
        end
      end)
    then
      h.expect_true(top.remove())
    end
    true
