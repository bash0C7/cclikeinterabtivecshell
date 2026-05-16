require "test/unit"
require "baslash/debug/embedder_pool"

class TestEmbedderPool < Test::Unit::TestCase
  def test_embedder_constants
    assert_equal 768, Baslash::Debug::EmbedderPool::VECTOR_SIZE
    assert_equal "mochiya98/ruri-v3-310m-onnx", Baslash::Debug::EmbedderPool::MODEL_NAME
  end

  def test_embed_returns_768_floats
    omit_unless ENV["BASLASH_DEBUG_TEST_EMBEDDER"] == "1"
    pool = Baslash::Debug::EmbedderPool.new
    vec = pool.embed("テスト")
    assert_equal 768, vec.size
    assert vec.all? { |f| f.is_a?(Float) }
  end
end
