# -*- coding: utf-8 -*-
miquire :core, 'userconfig'

require 'gtk2'
require 'monitor'
require_if_exist 'Win32API'

class GLib::Instantiatable
  # signal_connectと同じだが、イベントが呼ばれるたびにselfが削除されたGLib Objectでない場合のみブロックを実行する点が異なる。
  # また、relatedの中に既に削除されたGLib objectがあれば、ブロックを実行せずにシグナルをselfから切り離す。
  # ==== Args
  # [signal] イベント名か、イベントとブロックの連想配列
  #   Symbol|String :: イベントの名前
  #   Hash :: キーにイベント名、値に呼び出すブロックを持つHash
  # [*related] GLib::Object ブロック実行時、これらのうちどれか一つでも削除されていたらブロックを実行しない
  # [&proc] signalがイベントの名前の場合、イベントが発生したらこのブロックが呼ばれる
  # ==== Return
  # signal_connectと同じ
  def safety_signal_connect(signal, *related, &proc)
    case signal
    when Hash
      signal.each{ |name, callback|
        safety_signal_connect(name, *related, &callback) }
    when String, Symbol
      related.each{ |gobj|
        raise ArgumentError.new(gobj.to_s) unless gobj.is_a?(GLib::Object) }
      if related
        sid = signal_connect(signal){ |*args|
          if not(destroyed?)
            if (related.any?(&:destroyed?))
              signal_handler_disconnect(sid)
            else
              proc.call(*args) end end }
      else
        signal_connect(signal){ |*args|
          if not(destroyed?)
            proc.call(*args) end } end
    else
      raise ArgumentError, "First argument should Hash, String, or Symbol." end end
  alias ssc safety_signal_connect

  # safety_signal_connect を、イベントが発生した最初の一度だけ呼ぶ
  def safety_signal_connect_atonce(signal, *related, &proc)
    called = false
    sid = ssc(signal, *related) { |*args|
      unless called
        called = true
        signal_handler_disconnect(sid)
        proc.call(args) end }
    sid end
  alias ssc_atonce safety_signal_connect_atonce

  private
  def __track(&proc)
    type_strict proc => :call
    trace = caller(3)
    lambda{ |*args|
      begin
        proc.call(*args)
      rescue Exception => e
        now = caller.size + 1     # proc.callのぶんスタックが１つ多い
        $@ = e.backtrace[0, e.backtrace.size - now] + trace
        Gtk.exception = e
        into_debug_mode(e, proc.binding)
        raise e end
    }
  end

end

class Gtk::Object
  def self.main_quit
    Gtk.main_quit end end

module Gtk
  KonamiCache = File.expand_path(File.join(Environment::CACHE, 'core', 'konami.png'))
  class << self
    attr_accessor :exception, :konami
    attr_reader :konami_image
  end

  self.konami = false

  def self.konami_load
    return if @konami
    if FileTest.exist? KonamiCache
      @konami_image = Gdk::Pixbuf.new(KonamiCache, 41, 52)
      @konami = true
    else
      Thread.new do
        begin
          tmpfile = File.join(Environment::TMPDIR, '600eur')
          open('http://mikutter.hachune.net/img/konami.png', 'rb') { |konami|
            open(tmpfile, 'wb'){ |cache| IO.copy_stream konami, cache } }
          FileUtils.mkdir_p(File.dirname(KonamiCache))
          FileUtils.mv(tmpfile, KonamiCache)
          @konami_image = Gdk::Pixbuf.new(KonamiCache, 41, 52)
          @konami = true
        rescue => exception
          error exception end end end end

  def self.keyname(key)
    type_strict key => Array
    if key.empty? or key[0] == 0 or not key.all?(&ret_nth)
      return '(割り当てなし)'
    else
      r = ""
      r << 'Control + ' if (key[1] & Gdk::Window::CONTROL_MASK) != 0
      r << 'Shift + ' if (key[1] & Gdk::Window::SHIFT_MASK) != 0
      r << 'Alt + ' if (key[1] & Gdk::Window::MOD1_MASK) != 0
      r << 'Super + ' if (key[1] & Gdk::Window::SUPER_MASK) != 0
      r << 'Hyper + ' if (key[1] & Gdk::Window::HYPER_MASK) != 0
      return r + Gdk::Keyval.to_name(key[0]) end end

  def self.buttonname(key)
    type_strict key => Array
    type, button, state = key
    if key.empty? or type == 0 or not key.all?(&ret_nth)
      return '(割り当てなし)'
    else
      r = ""
      r << 'Control + ' if (state & Gdk::Window::CONTROL_MASK) != 0
      r << 'Shift + ' if (state & Gdk::Window::SHIFT_MASK) != 0
      r << 'Alt + ' if (state & Gdk::Window::MOD1_MASK) != 0
      r << 'Super + ' if (state & Gdk::Window::SUPER_MASK) != 0
      r << 'Hyper + ' if (state & Gdk::Window::HYPER_MASK) != 0
      r << "Button #{button} "
      case type
      when Gdk::Event::BUTTON_PRESS
          r << 'Click'
      when Gdk::Event::BUTTON2_PRESS
          r << 'Double Click'
      when Gdk::Event::BUTTON3_PRESS
          r << 'Triple Click'
      else
        return '(割り当てなし)' end
      return r end end

end

=begin rdoc
= Gtk::Lock Ruby::Gnome2の排他制御
メインスレッド以外でロックしようとするとエラーを発生させる。
Gtkを使うところで、メインスレッドではない疑いがある箇所は必ずGtk::Lockを使う。
=end
class Gtk::Lock
  # ブロック実行前に _lock_ し、実行後に _unlock_ する。
  # ブロックの実行結果を返す。
  def self.synchronize
    begin
      lock
      yield
    ensure
      unlock
    end
  end

  # メインスレッド以外でこの関数を呼ぶと例外を発生させる。
  def self.lock
    raise 'Gtk lock can mainthread only' if Thread.main != Thread.current
  end

  def self.unlock
  end
end

class Gtk::Widget < Gtk::Object
  # ウィジェットを上寄せで配置する
  def top
    Gtk::Alignment.new(0.0, 0, 0, 0).add(self)
  end

  # ウィジェットを横方向に中央寄せで配置する
  def center
    Gtk::Alignment.new(0.5, 0, 0, 0).add(self)
  end

  # ウィジェットを左寄せで配置する
  def left
    Gtk::Alignment.new(0, 0, 0, 0).add(self)
  end

  # ウィジェットを右寄せで配置する
  def right
    Gtk::Alignment.new(1.0, 0, 0, 0).add(self)
  end

  # ウィジェットにツールチップ _text_ をつける
  def tooltip(text)
    Gtk::Tooltips.new.set_tip(self, text, '')
    self end
end

class Gtk::Container < Gtk::Widget
  # _widget_ を詰めて配置する。closeupで配置されたウィジェットは無理に親の幅に合わせられることがない。
  # pack_start(_widget_, false)と等価。
  def closeup(widget)
    self.pack_start(widget, false)
  end
end

class Gtk::TextBuffer < GLib::Object
  # _idx_ 文字目を表すイテレータと、そこから _size_ 文字後ろを表すイテレータの2要素からなる配列を返す。
  def get_range(idx, size)
    [self.get_iter_at_offset(idx), self.get_iter_at_offset(idx + size)]
  end
end

class Gtk::Clipboard
  # 文字列 _t_ をクリップボードにコピーする
  def self.copy(t)
    Gtk::Clipboard.get(Gdk::Atom.intern('CLIPBOARD', true)).text = t
  end

  # クリップボードから文字列を取得する
  def self.paste
    Gtk::Clipboard.get(Gdk::Atom.intern('CLIPBOARD', true)).wait_for_text
  end
end

class Gtk::Dialog
  # メッセージダイアログを表示する。
  def self.alert(message)
    Gtk::Lock.synchronize{
      dialog = Gtk::MessageDialog.new(nil,
                                      Gtk::Dialog::DESTROY_WITH_PARENT,
                                      Gtk::MessageDialog::QUESTION,
                                      Gtk::MessageDialog::BUTTONS_CLOSE,
                                      message)
      dialog.run
      dialog.destroy
    }
  end

  # Yes,Noの二択の質問を表示する。
  # YESボタンが押されたらtrue、それ以外が押されたらfalseを返す
  def self.confirm(message)
    Gtk::Lock.synchronize{
      dialog = Gtk::MessageDialog.new(nil,
                                      Gtk::Dialog::DESTROY_WITH_PARENT,
                                      Gtk::MessageDialog::QUESTION,
                                      Gtk::MessageDialog::BUTTONS_YES_NO,
                                      message)
      res = dialog.run
      dialog.destroy
      res == Gtk::Dialog::RESPONSE_YES
    }
  end
end

class Gtk::Notebook
  # ラベルウィジェットが何番目のタブかを返す
  # ==== Args
  # [label] ラベルウィジェット
  # ==== Return
  # インデックス(見つからない場合nil)
  def get_tab_pos_by_tab(label)
    n_pages.times { |page_num|
      if(get_tab_label(get_nth_page(page_num)) == label)
        return page_num end }
    nil end
end

class Gtk::ListStore
  def model
    self end
end

module Gtk
  # _url_ を設定されているブラウザで開く
  class << self
    def openurl(url)
      command = nil
      if UserConfig[:url_open_specified_command]
        command = UserConfig[:url_open_command]
        bg_system(command, url)
      elsif(defined? Win32API) then
        shellExecuteA = Win32API.new('shell32.dll','ShellExecuteA',%w(p p p p p i),'i')
        shellExecuteA.call(0, 'open', url, 0, 0, 1)
      else
        command = Gtk::url_open_command
        if(command)
          bg_system(command, url)
        else
          Plugin.activity :system, "この環境で、URLを開くためのコマンドが判別できませんでした。設定の「表示→URLを開く方法」で、URLを開く方法を設定してください。" end end
    rescue => e
      Plugin.activity :system, "コマンド \"#{command}\" でURLを開こうとしましたが、開けませんでした。設定の「表示→URLを開く方法」で、URLを開く方法を設定してください。" end

    # URLを開くことができるコマンドを返す。
    def url_open_command
      openable_commands = %w{xdg-open open /etc/alternatives/x-www-browser}
      wellknown_browsers = %w{firefox chromium opera}
      command = nil
      catch(:urlopen) do
        openable_commands.each{ |o|
          if command_exist?(o)
            command = o
            throw :urlopen end }
        wellknown_browsers.each{ |o|
          if command_exist?(o)
            Plugin.activity :system, "この環境で、URLを開くためのコマンドが判別できなかったので、\"#{command}\"を使用します。設定の「表示→URLを開く方法」で、URLを開く方法を設定してください。"
            command = o
            throw :urlopen end } end
      command end
    memoize :url_open_command
  end
end

module MUI
  Skin = ::Skin
end
